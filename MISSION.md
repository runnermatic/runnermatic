## Runnermatic Mission Orders

**Prerequisites:** Run `PREFLIGHT.md` first. It handles git init, env files, gh auth, service user, and runner directory setup.

### Environment

- Org: `runnermatic`
- GitHub App: `runnermatic-tokenizer`, installed on `runnermatic` with org **Self-hosted runners: read & write**
- Project root: `~/runnermatic`
- Config: `config/org.env` (PAT + org settings), `config/app.env` (App settings)
- PEM: `config/runnermatic-tokenizer.pem`
- Tools: `curl`, `jq`, `git`, `gh` (authenticated), `node`, `fnm`
- `sudo` is available for systemd and `/srv/` operations
- Runner dirs: `/srv/github-runner-{1..4}` (pre-populated with runner binary)
- Service user: `github-runner`

### How to work

1. **Read `NOTES.md` first** to see what's already been completed in previous iterations.
2. Work through the sections below in order, skipping any that are already done.
3. After completing each section, **append results to `NOTES.md`** with the section number, what you did, and verification output.
4. Every step must be **idempotent** — check before acting, skip if already done.
5. When all sections are complete and verified, output `<promise>MISSION COMPLETE</promise>`.

### Script conventions

- All scripts resolve paths relative to project root:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  ```
- Scripts that need the PAT: `source "$PROJECT_ROOT/config/org.env"` and use `$GITHUB_PAT`.
- Scripts that need App credentials: `source "$PROJECT_ROOT/config/app.env"`.

***

### 1. Repo structure

Create the following files (skip any that already exist) and make an initial commit:

- `scripts/register-runner-with-pat.sh`
- `scripts/register-runner-with-app.sh`
- `scripts/configure-runner.sh`
- `scripts/manage-runners.sh`
- `scripts/generate-jwt.js`
- `systemd/github-runner@.service`
- `workflows/four-runners-test.yml`

**Done when:** `git log` shows the initial commit and all files exist.

***

### 2. PAT-based registration (bootstrap)

Implement `scripts/register-runner-with-pat.sh`:

- Source `config/org.env`.
- Use `gh api` to call the org-level runner registration token endpoint:
  ```bash
  gh api --method POST /orgs/$GITHUB_ORG/actions/runners/registration-token --jq '.token'
  ```
- Print the token to stdout.

Implement `scripts/configure-runner.sh`:

- Accept: `MODE` (`pat` or `app`), `INDEX` (1-4), optional labels (default: `self-hosted,lab`).
- Check if `/srv/github-runner-$INDEX/.runner` exists — if so, skip (already configured).
- In `MODE=pat`, call `register-runner-with-pat.sh` to get a token.
- Run `./config.sh` in `/srv/github-runner-$INDEX` as the `github-runner` user with:
  - `--url https://github.com/$GITHUB_ORG`
  - `--token <token>`
  - `--name runnermatic-$INDEX`
  - `--labels <labels>`
  - `--unattended`

Configure runners 1-4 in PAT mode.

**Verify:**
```bash
gh api /orgs/runnermatic/actions/runners --jq '.runners[].name'
```

**Done when:** All 4 runners appear in the API response.

***

### 3. systemd multi-runner

Create `systemd/github-runner@.service`:

```ini
[Unit]
Description=GitHub Actions Runner %i
After=network.target

[Service]
User=github-runner
WorkingDirectory=/srv/github-runner-%i
ExecStart=/srv/github-runner-%i/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Implement `scripts/manage-runners.sh` supporting:

- `install-unit` — copy unit to `/etc/systemd/system/`, `sudo systemctl daemon-reload`.
- `start N` / `stop N` — start/stop `github-runner@N.service`.
- `start-all` / `stop-all` — for indices 1-4.
- `status` — show status of all 4 runner services.

Install the unit and run `start-all`.

**Verify:**
```bash
scripts/manage-runners.sh status
gh api /orgs/runnermatic/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

**Done when:** All 4 runners show `online` in the API response.

***

### 4. Create the test repo

Using `gh`:

1. Create repo `runner-test-repo` in the `runnermatic` org (skip if it already exists):
   ```bash
   gh repo view runnermatic/runner-test-repo >/dev/null 2>&1 || \
     gh repo create runnermatic/runner-test-repo --public
   ```

2. Push `workflows/four-runners-test.yml` to the repo as `.github/workflows/four-runners-test.yml`.

The workflow should have:
- `on: workflow_dispatch`
- Four jobs (`job-1` through `job-4`), each with `runs-on: [self-hosted, lab]`
- Each job prints its name, runner name (`${{ runner.name }}`), hostname, and sleeps 10s.

**Verify:**
```bash
gh repo view runnermatic/runner-test-repo
gh api /repos/runnermatic/runner-test-repo/actions/workflows --jq '.workflows[].name'
```

**Done when:** Repo exists and workflow is listed.

***

### 5. App-based registration (core objective)

Implement `scripts/generate-jwt.js`:

- Read `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY_PATH` from environment (or accept as args).
- Build an RS256-signed JWT using Node.js built-in `crypto` module (no npm packages):
  - `iss` = `GITHUB_APP_ID`
  - `iat` = now minus 60 seconds
  - `exp` = now plus 10 minutes
- Print the JWT to stdout.

Implement `scripts/register-runner-with-app.sh`:

- Source `config/app.env`.
- Generate a JWT via `scripts/generate-jwt.js`.
- Get an installation access token:
  ```bash
  curl -s -X POST \
    -H "Authorization: Bearer $JWT" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens" \
    | jq -r '.token'
  ```
- Use that token to get a runner registration token:
  ```bash
  curl -s -X POST \
    -H "Authorization: Bearer $INSTALL_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$GITHUB_ORG/actions/runners/registration-token" \
    | jq -r '.token'
  ```
- Print the registration token to stdout.

Update `scripts/configure-runner.sh`:

- In `MODE=app`, call `register-runner-with-app.sh` instead of the PAT script.

**Verify:** Run `scripts/register-runner-with-app.sh` and confirm it prints a valid token.

**Done when:** The script outputs a registration token without using the PAT.

***

### 6. Workflow test with PAT-registered runners

1. Ensure all 4 runners are started: `scripts/manage-runners.sh start-all`.
2. Trigger the workflow:
   ```bash
   gh workflow run four-runners-test.yml -R runnermatic/runner-test-repo
   ```
3. Wait and check:
   ```bash
   sleep 30
   gh run list -R runnermatic/runner-test-repo --workflow=four-runners-test.yml -L 1 --json status,conclusion
   ```

**Done when:** The workflow run shows `conclusion: "success"`.

***

### 7. App-only rebuild and final test

1. Stop all runners: `scripts/manage-runners.sh stop-all`.
2. Remove existing registrations:
   ```bash
   for i in 1 2 3 4; do
     sudo -u github-runner /srv/github-runner-$i/config.sh remove --token "$(scripts/register-runner-with-pat.sh)"
   done
   ```
3. Re-register all 4 runners using **only** `MODE=app`:
   ```bash
   for i in 1 2 3 4; do
     scripts/configure-runner.sh app $i
   done
   ```
4. Start all: `scripts/manage-runners.sh start-all`.
5. Trigger the workflow again and verify success:
   ```bash
   gh workflow run four-runners-test.yml -R runnermatic/runner-test-repo
   sleep 30
   gh run list -R runnermatic/runner-test-repo --workflow=four-runners-test.yml -L 1 --json status,conclusion
   ```

**Verify:**
```bash
gh api /orgs/runnermatic/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

**Done when:** All 4 runners are online, registered via App only, and the workflow run succeeds. Document everything in `NOTES.md`.
