# Runnermatic Security Assessment

**Date:** 2026-03-04
**Scope:** Self-hosted GitHub Actions runner registration and management via GitHub App
**Classification:** Internal

---

## Executive Summary

Runnermatic registers and manages self-hosted GitHub Actions runners using a GitHub App with minimal permissions (Self-hosted runners: Read & write only). This replaces long-lived PAT-based registration with short-lived, scoped tokens derived from App credentials.

**Overall Risk Rating: Medium**

The primary risk is the PEM private key — a static credential that, if compromised, allows an attacker to register rogue runners on the organization. This is mitigated by the App's narrow permission scope, short-lived derived tokens, and file-system access controls. The self-hosted runners themselves present the larger attack surface, as they execute arbitrary code from workflows.

---

## Authentication Architecture

### Two Authentication Paths

| Path | Purpose | Credentials | Token Lifetime |
|------|---------|-------------|----------------|
| **GitHub App** (primary) | Runner registration | PEM private key (static) | JWT: 10 min, Install token: 1 hr, Reg token: 1 hr / single-use |
| **PAT** (bootstrap) | Initial setup, convenience | Fine-grained PAT (static) | Until revoked |

### App-Based Token Chain

```
PEM Private Key (static, on disk)
    |
    v
JWT (RS256 signed, 10 min expiry)
    |
    v
POST /app/installations/{id}/access_tokens
    |
    v
Installation Access Token (1 hour expiry, scoped to org)
    |
    v
POST /orgs/{org}/actions/runners/registration-token
    |
    v
Runner Registration Token (1 hour expiry, single-use)
    |
    v
config.sh --token <reg-token> (consumed immediately)
```

Each token in the chain is strictly shorter-lived and more narrowly scoped than its predecessor. The registration token is consumed on use and cannot be replayed.

### PAT Bootstrap Path

The PAT is used only for:
- `gh` CLI authentication (repo management, workflow triggers)
- Fallback runner registration via `register-runner-with-pat.sh`

It is **not required** for the App-based registration flow.

---

## Threat Model

### Assets

| Asset | Location | Sensitivity |
|-------|----------|-------------|
| PEM private key | `config/runnermatic-tokenizer.pem` | **Critical** — enables App impersonation |
| PAT | `config/org.env` (GITHUB_PAT field) | **High** — org-level access |
| Installation access tokens | In-memory (scripts) | **Medium** — 1 hr expiry, scoped |
| Registration tokens | In-memory (scripts) | **Low** — single-use, 1 hr expiry |
| Runner hosts (`/srv/github-runner-*`) | Local filesystem | **High** — execute workflow code |
| App ID + Installation ID | `config/app.env` | **Low** — not secrets (public in API responses) |

### Threat Actors

| Actor | Motivation | Capability |
|-------|-----------|------------|
| External attacker | Access to org infrastructure | Network/web exploitation |
| Malicious workflow author | Code execution on runner hosts | Submit PRs with workflow changes |
| Insider (compromised developer) | Credential theft, lateral movement | Access to repo, possibly host |
| Supply chain attacker | Runner binary tampering | Compromise upstream runner releases |

### Attack Vectors

| # | Vector | Target Asset | Actor |
|---|--------|-------------|-------|
| 1 | PEM key exfiltration from host | PEM key | Insider, attacker with host access |
| 2 | PAT leak via git commit | PAT | Insider, automated scanners |
| 3 | Rogue runner registration | Org runner pool | Attacker with PEM or PAT |
| 4 | Workflow injection on self-hosted runner | Runner host | Malicious workflow author |
| 5 | Runner escape / host compromise | Host OS | Workflow code execution |
| 6 | Man-in-the-middle on token exchange | Tokens in transit | Network attacker |
| 7 | Compromised runner binary | Runner process | Supply chain attacker |
| 8 | Env file read via workflow | PAT, App credentials | Malicious workflow step |

---

## Risk Matrix

| # | Risk | Likelihood | Impact | Severity | Mitigation Status |
|---|------|-----------|--------|----------|-------------------|
| 1 | PEM key exfiltration | Low | Critical | **High** | File permissions (600), .gitignore |
| 2 | PAT committed to git | Low | High | **Medium** | .gitignore excludes config/*.env |
| 3 | Rogue runner registration | Low | High | **Medium** | App scoped to single org, tokens short-lived |
| 4 | Workflow injection | Medium | High | **High** | Requires PR merge / branch access |
| 5 | Runner escape | Low | Critical | **High** | Dedicated service user, no root |
| 6 | MITM token interception | Very Low | Medium | **Low** | All API calls over HTTPS/TLS |
| 7 | Compromised runner binary | Very Low | Critical | **Medium** | Downloaded from GitHub releases |
| 8 | Env file read via workflow | Medium | High | **High** | Runner dirs separate from project |

---

## Security Controls in Place

### 1. Credential Protection

| Control | Detail |
|---------|--------|
| `.gitignore` | Excludes `config/org.env`, `config/app.env`, `config/*.pat`, `config/*.pem` |
| File permissions | PEM should be `chmod 600`, readable only by owner |
| No hardcoded secrets | Scripts read credentials from env files at runtime |
| Separate config from code | Sensitive config lives in `config/` (gitignored), code is committed |

### 2. Least Privilege

| Control | Detail |
|---------|--------|
| GitHub App permissions | **Only** Self-hosted runners: Read & write — cannot read code, issues, or org settings |
| Service user | `github-runner` is a system user with `nologin` shell — no interactive access |
| Runner isolation | Each runner runs in its own `/srv/github-runner-N` directory |
| PAT fine-grained | Scoped to specific repository and org permissions (not classic token) |

### 3. Short-Lived Tokens

| Token | Lifetime | Scope |
|-------|----------|-------|
| JWT | 10 minutes | App identity only |
| Installation token | 1 hour | Org-level, App permissions only |
| Registration token | 1 hour, single-use | Runner registration only |

An attacker who intercepts a registration token can register one rogue runner, but cannot escalate to broader org access. The token cannot be reused.

### 4. Process Isolation

| Control | Detail |
|---------|--------|
| Dedicated user | Runners execute as `github-runner`, not root |
| systemd management | `Restart=always` ensures runners recover from crashes |
| Separate working dirs | Each runner has its own `/srv/github-runner-N` workspace |

---

## Attack Surface Analysis (Technical Appendix)

### A. PEM Key Exposure

The PEM private key is the most sensitive credential. If compromised, an attacker can:

1. Generate valid JWTs
2. Obtain installation access tokens
3. Register rogue runners on the org
4. Potentially list/remove existing runners

**Cannot** do with PEM alone:
- Read repository code (App lacks Contents permission)
- Modify org settings (App lacks Administration permission)
- Access secrets/variables (App lacks Secrets permission)
- Trigger workflows (App lacks Actions permission)

**Mitigations:**
- Store PEM with `chmod 600` ownership by a service account
- Consider moving PEM to a secrets manager (HashiCorp Vault, AWS Secrets Manager)
- Monitor GitHub App audit log for unexpected token generation
- Rotate the PEM key periodically (GitHub allows generating new keys)

### B. JWT Implementation

`scripts/generate-jwt.js` uses Node.js built-in `crypto.createSign('RSA-SHA256')`.

**Strengths:**
- No third-party dependencies (no npm supply chain risk)
- Standard RS256 signing
- Clock skew handled (`iat = now - 60s`)

**Considerations:**
- JWT expiry set to maximum (10 min) — could be reduced for tighter windows
- No audience (`aud`) claim — GitHub doesn't require it for App JWTs
- PEM loaded from disk on every invocation — no caching of sensitive material in memory

### C. Runner Process Security

Self-hosted runners execute **arbitrary code** defined in workflows. This is the largest attack surface.

**Risks:**
- Workflows can access the runner filesystem
- Workflows can read environment variables accessible to the runner process
- Workflows can install software, open network connections
- A malicious PR could modify workflow files (if auto-merge is enabled)

**Current mitigations:**
- Runners run as `github-runner` (non-root, nologin)
- Runner directories are separate from the project directory
- Config files (with secrets) are in the project dir, not the runner dir

**Gaps:**
- Runners are **persistent** (not ephemeral) — artifacts from previous jobs may leak to subsequent jobs
- No container isolation — jobs run directly on the host
- The `github-runner` user could potentially access other runner directories

### D. Network Exposure

- All GitHub API communication is HTTPS/TLS
- Runners maintain a long-poll HTTPS connection to GitHub (outbound only)
- No inbound ports required
- Runner registration tokens transit via HTTPS API responses

### E. Workflow File Injection

If an attacker can push to a branch that triggers workflows on self-hosted runners, they gain code execution as `github-runner`. Protections:

- `workflow_dispatch` trigger requires write access to the repo
- Branch protection rules can restrict who can push workflow changes
- Fine-grained PAT's `Workflows: R/W` permission should be limited to admin users

---

## Recommendations

### Immediate (before production)

| # | Recommendation | Priority | Effort |
|---|---------------|----------|--------|
| 1 | Set PEM file permissions to `chmod 600` | **Critical** | Low |
| 2 | Restrict who can modify workflow files in repos using self-hosted runners | **High** | Low |
| 3 | Enable branch protection on repos that trigger self-hosted runner jobs | **High** | Low |
| 4 | Audit GitHub App permissions — confirm only Self-hosted runners R/W is granted | **High** | Low |
| 5 | Configure runner group to restrict which repos can use self-hosted runners | **High** | Low |

### Short-term (within 30 days)

| # | Recommendation | Priority | Effort |
|---|---------------|----------|--------|
| 6 | Move PEM key and PAT to a secrets manager (Vault, AWS SM, etc.) | **High** | Medium |
| 7 | Add systemd hardening directives (see below) | **Medium** | Low |
| 8 | Set up monitoring/alerting on GitHub App audit log for unexpected activity | **Medium** | Medium |
| 9 | Implement ephemeral runners (re-provision after each job) | **Medium** | High |

### Long-term

| # | Recommendation | Priority | Effort |
|---|---------------|----------|--------|
| 10 | Run runners in containers (Docker/Podman) for job isolation | **High** | High |
| 11 | Implement network segmentation — runners in a dedicated VLAN/subnet | **Medium** | High |
| 12 | Establish PEM key rotation schedule (quarterly recommended) | **Medium** | Low |
| 13 | Consider GitHub's larger runner offerings if scaling beyond single host | **Low** | Medium |

### systemd Hardening (Recommendation #7)

Add to `github-runner@.service`:

```ini
[Service]
# Existing directives...
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
ReadWritePaths=/srv/github-runner-%i
```

This restricts the runner process from writing outside its designated directory.

---

## Compliance Considerations

### SOC 2 Relevance

| Control Area | Status | Notes |
|-------------|--------|-------|
| Access Control (CC6.1) | Partial | App uses least privilege; PAT should be time-limited |
| Logical Access (CC6.3) | Met | Fine-grained PAT + App scoping |
| System Operations (CC7.1) | Partial | Need monitoring/alerting on runner registration |
| Change Management (CC8.1) | Met | All code in git, .gitignore protects secrets |
| Risk Assessment (CC3.2) | Met | This document |

### GitHub Shared Responsibility

GitHub secures the Actions platform and hosted runners. For **self-hosted runners**, the organization is responsible for:

- Host OS patching and hardening
- Runner binary updates
- Network security
- Secret management on the host
- Job isolation between workflow runs
- Physical/virtual security of the runner host

GitHub provides:
- Encrypted communication (TLS)
- Token generation and validation
- Audit logging for runner registration/removal
- Runner group access controls

---

## Appendix: Token Scope Comparison

| Capability | PAT (current) | GitHub App | Installation Token |
|-----------|--------------|------------|-------------------|
| Create repos | Yes (Administration R/W) | No | No |
| Push code | Yes (Contents R/W) | No | No |
| Trigger workflows | Yes (Actions R/W) | No | No |
| Register runners | Yes (Self-hosted runners R/W) | N/A (uses token chain) | Yes |
| List runners | Yes | N/A | Yes |
| Remove runners | Yes | N/A | Yes |
| Read code | Yes (Contents R/W) | No | No |
| Manage org settings | Yes (Administration R/W) | No | No |

The GitHub App's installation token can **only** manage runners. This is the key security advantage over PAT-based registration.
