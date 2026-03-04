# Runnermatic Implementation Guide

## Overview

Runnermatic is a self-hosted GitHub Actions runner management system that registers and manages runners using a **GitHub App** instead of personal access tokens. This eliminates PAT rotation concerns and provides scoped, short-lived credentials for runner registration.

```
                          GitHub API
                              |
              +---------------+---------------+
              |                               |
         PAT (bootstrap)              GitHub App (primary)
              |                               |
              v                               v
    gh api /registration-token     PEM key -> JWT -> Install Token
                                              |
                                              v
                                     Registration Token
                                              |
              +-------------------------------+
              |
              v
    config.sh --token <TOKEN> --name runnermatic-N
              |
    +---------+---------+---------+
    |         |         |         |
  Runner 1  Runner 2  Runner 3  Runner 4
  (systemd) (systemd) (systemd) (systemd)
```

### Components

| Component | Path | Purpose |
|-----------|------|---------|
| `register-runner-with-pat.sh` | `scripts/` | PAT-based registration token (bootstrap) |
| `register-runner-with-app.sh` | `scripts/` | App-based registration token (primary) |
| `generate-jwt.js` | `scripts/` | RS256 JWT generation for GitHub App auth |
| `configure-runner.sh` | `scripts/` | Runner configuration (accepts `pat` or `app` mode) |
| `manage-runners.sh` | `scripts/` | systemd lifecycle management |
| `github-runner@.service` | `systemd/` | Templated systemd unit |
| `org.env` | `config/` | Org settings + PAT |
| `app.env` | `config/` | GitHub App credentials |

---

## Prerequisites

### Host Requirements

- Linux x64 (tested on Ubuntu 22.04+)
- `curl`, `jq`, `git`, `gh` (GitHub CLI), `node` (v16+)
- `sudo` access for systemd and `/srv/` operations
- Outbound HTTPS to `github.com` and `api.github.com`

### GitHub Organization

- A GitHub org (e.g., `runnermatic`)
- Owner or admin access to the org

---

## Step 1: Create the GitHub App

1. Go to **Organization Settings > Developer settings > GitHub Apps > New GitHub App**
2. Configure:

| Field | Value |
|-------|-------|
| App name | `<your-org>-tokenizer` (or any unique name) |
| Homepage URL | Your org URL or repo URL |
| Webhook | **Uncheck** "Active" (not needed) |

3. **Permissions** - set only:

| Category | Permission | Access |
|----------|-----------|--------|
| Organization permissions | Self-hosted runners | **Read & write** |

No other permissions are needed. This is the minimum scope for runner registration.

4. **Where can this GitHub App be installed?** > "Only on this account"

5. Click **Create GitHub App**

6. Note the **App ID** from the App settings page

7. **Generate a private key** - download the `.pem` file

8. **Install the App** on your organization:
   - Go to the App's settings > Install App > select your org
   - Grant access to "All repositories" (or selected repos if preferred)
   - Note the **Installation ID** from the URL: `https://github.com/organizations/<org>/settings/installations/<INSTALLATION_ID>`

---

## Step 2: Configure the Project

### Clone and set up config files

```bash
git clone https://github.com/<org>/runnermatic.git
cd runnermatic

cp -n config/org.env.example config/org.env
cp -n config/app.env.example config/app.env
```

### Edit `config/org.env`

```bash
GITHUB_ORG=<your-org>
GITHUB_BASE_URL=https://github.com
GITHUB_API_URL=https://api.github.com
GITHUB_PAT=<your-fine-grained-PAT>  # only needed for bootstrap/convenience
```

The PAT is optional if you only use App-based registration. If used, it needs:
- **Repository permissions**: Contents (R/W), Actions (R/W), Workflows (R/W), Metadata (read)
- **Organization permissions**: Self-hosted runners (R/W), Administration (R/W)

### Edit `config/app.env`

```bash
GITHUB_ORG=<your-org>
GITHUB_BASE_URL=https://github.com
GITHUB_API_URL=https://api.github.com
GITHUB_APP_NAME=<your-app-name>
GITHUB_APP_ID=<numeric App ID>
GITHUB_APP_INSTALLATION_ID=<numeric Installation ID>
GITHUB_APP_PRIVATE_KEY_PATH=/absolute/path/to/your-app.pem
```

### Place the PEM file

```bash
cp ~/Downloads/<your-app>.pem config/
chmod 600 config/*.pem
```

---

## Step 3: Prepare the Host

### Create service user

```bash
sudo useradd --system --shell /usr/sbin/nologin github-runner
```

### Create runner directories

```bash
sudo mkdir -p /srv/github-runner-{1,2,3,4}
```

### Download and extract the runner binary

```bash
RUNNER_URL=$(curl -sL https://api.github.com/repos/actions/runner/releases/latest \
  | jq -r '.assets[] | select(.name | test("actions-runner-linux-x64-.+\\.tar\\.gz$")) | .browser_download_url')

curl -sL "$RUNNER_URL" -o /tmp/actions-runner.tar.gz

for i in 1 2 3 4; do
  sudo tar -xzf /tmp/actions-runner.tar.gz -C /srv/github-runner-$i
done

sudo chown -R github-runner:github-runner /srv/github-runner-{1,2,3,4}
```

---

## Step 4: Register Runners

### Using GitHub App (recommended)

```bash
for i in 1 2 3 4; do
  scripts/configure-runner.sh app $i
done
```

### Using PAT (bootstrap alternative)

```bash
gh auth login --with-token <<< "$(grep GITHUB_PAT config/org.env | cut -d= -f2)"

for i in 1 2 3 4; do
  scripts/configure-runner.sh pat $i
done
```

### How App-based registration works

```
1. scripts/configure-runner.sh app N
   |
   +-> scripts/register-runner-with-app.sh
       |
       +-> source config/app.env
       |   (loads GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, PEM path)
       |
       +-> scripts/generate-jwt.js
       |   Reads PEM key, builds RS256 JWT:
       |     header:  { alg: "RS256", typ: "JWT" }
       |     payload: { iss: APP_ID, iat: now-60s, exp: now+10m }
       |   Signs with private key, outputs JWT string
       |
       +-> POST /app/installations/{id}/access_tokens
       |   Authorization: Bearer <JWT>
       |   Returns: installation access token (1hr expiry)
       |
       +-> POST /orgs/{org}/actions/runners/registration-token
       |   Authorization: Bearer <installation-token>
       |   Returns: runner registration token (single-use, 1hr expiry)
       |
   +-> sudo -u github-runner /srv/github-runner-N/config.sh
       --url https://github.com/<org>
       --token <registration-token>
       --name runnermatic-N
       --labels self-hosted,lab
       --unattended
```

---

## Step 5: systemd Management

### Install the unit template

```bash
scripts/manage-runners.sh install-unit
```

This copies `systemd/github-runner@.service` to `/etc/systemd/system/` and reloads systemd.

### Lifecycle commands

```bash
scripts/manage-runners.sh start-all       # start runners 1-4
scripts/manage-runners.sh stop-all        # stop runners 1-4
scripts/manage-runners.sh start 2         # start runner 2 only
scripts/manage-runners.sh stop 3          # stop runner 3 only
scripts/manage-runners.sh status          # show all runner statuses
```

---

## Step 6: Verify

### Check runners are online

```bash
gh api /orgs/<org>/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

Expected:
```
runnermatic-1: online
runnermatic-2: online
runnermatic-3: online
runnermatic-4: online
```

### Run a test workflow

```bash
gh workflow run four-runners-test.yml -R <org>/runner-test-repo
sleep 30
gh run list -R <org>/runner-test-repo --workflow=four-runners-test.yml -L 1 --json status,conclusion
```

Expected: `[{"conclusion":"success","status":"completed"}]`

---

## Troubleshooting

### PAT returns 403 on runner endpoints

Fine-grained PATs require **explicit** "Self-hosted runners: Read & write" under Organization permissions. Org admin does not imply this.

### Workflows stuck in "queued"

The default org runner group has `allows_public_repositories: false`. For public repos:

```bash
echo '{"allows_public_repositories":true}' | \
  gh api /orgs/<org>/actions/runner-groups/1 -X PATCH --input -
```

### `generate-jwt.js` fails with "GITHUB_APP_ID not set"

The `register-runner-with-app.sh` script must `export` the variables after sourcing `app.env`:

```bash
source "$PROJECT_ROOT/config/app.env"
export GITHUB_APP_ID GITHUB_APP_PRIVATE_KEY_PATH
```

### Git push rejected for workflow files

Fine-grained PATs need the **Workflows: Read & write** repository permission to push files under `.github/workflows/`.

### Runner says "connected" but no jobs picked up

Verify labels match. Check with:
```bash
gh api /orgs/<org>/actions/runners --jq '.runners[] | "\(.name): \(.labels | map(.name) | join(", "))"'
```

Workflow `runs-on` must match a subset of the runner's labels.

---

## Scaling

To add more runners, repeat for each new index:

```bash
sudo mkdir -p /srv/github-runner-N
sudo tar -xzf /tmp/actions-runner.tar.gz -C /srv/github-runner-N
sudo chown -R github-runner:github-runner /srv/github-runner-N
scripts/configure-runner.sh app N
sudo systemctl start github-runner@N.service
```

Update `manage-runners.sh` to adjust the `start-all`/`stop-all` range if needed.
