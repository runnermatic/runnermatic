# Runnermatic

Self-hosted GitHub Actions runner management using GitHub App authentication.

Registers and manages org-level runners with short-lived, scoped tokens instead of long-lived PATs. A GitHub App with **only** Self-hosted runners: Read & write permission generates registration tokens through a three-step token chain:

```
PEM Key --> JWT (10 min) --> Installation Token (1 hr) --> Registration Token (single-use)
```

## Quick Start

```bash
# Configure
cp config/org.env.example config/org.env    # add PAT (optional, for bootstrap)
cp config/app.env.example config/app.env    # add App ID, Installation ID, PEM path

# Register runners via GitHub App
scripts/configure-runner.sh app 1
scripts/configure-runner.sh app 2
scripts/configure-runner.sh app 3
scripts/configure-runner.sh app 4

# Start with systemd
scripts/manage-runners.sh install-unit
scripts/manage-runners.sh start-all
```

## How It Works

The GitHub App path (`scripts/register-runner-with-app.sh`) avoids PATs entirely:

1. `generate-jwt.js` signs an RS256 JWT using the App's PEM private key (Node.js built-in `crypto`, no npm dependencies)
2. The JWT is exchanged for a short-lived installation access token via GitHub's API
3. The installation token requests a single-use runner registration token
4. `config.sh` consumes the registration token to bind the runner to the org

A PAT-based fallback (`scripts/register-runner-with-pat.sh`) is available for bootstrap scenarios.

## Project Structure

```
scripts/
  configure-runner.sh          # Register a runner (accepts 'pat' or 'app' mode)
  register-runner-with-app.sh  # App-based token acquisition
  register-runner-with-pat.sh  # PAT-based token acquisition
  generate-jwt.js              # RS256 JWT generation for GitHub App auth
  manage-runners.sh            # systemd lifecycle (start/stop/status)
config/
  org.env.example              # Org settings + PAT template
  app.env.example              # GitHub App credentials template
systemd/
  github-runner@.service       # Templated unit for multi-runner management
workflows/
  four-runners-test.yml        # Validation workflow (4 parallel jobs)
docs/
  implementation-guide.md      # Full setup walkthrough
  security-assessment.md       # Threat model, risk matrix, recommendations
```

## GitHub App Setup

**Option A: Use the existing App** — Install [runnermatic-tokenizer](https://github.com/apps/runnermatic-tokenizer) on your org. Quick and easy — same PEM key works across all installations, you just need the new Installation ID.

**Option B: Create your own App** — Create a GitHub App under your own org so your team controls the PEM key, rotation, and revocation independently. This is recommended for production or if your security team requires full ownership of credentials. The setup takes 5 minutes:

1. Create a GitHub App in your org with **one permission**: Organization > Self-hosted runners: Read & write
2. Generate a private key (PEM) and note the App ID
3. Install the App on your org and note the Installation ID
4. Configure `config/app.env` with those values

See [docs/implementation-guide.md](docs/implementation-guide.md) for detailed steps.

## Requirements

- Linux x64
- Node.js 16+ (for JWT generation)
- `curl`, `jq`, `gh` (GitHub CLI)
- `sudo` access (for systemd and `/srv/` operations)

## Documentation

- [Implementation Guide](docs/implementation-guide.md) — Full setup and deployment walkthrough
- [Security Assessment](docs/security-assessment.md) — Threat model, risk matrix, and hardening recommendations

## License

MIT
