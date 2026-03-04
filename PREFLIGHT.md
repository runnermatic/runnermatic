# Runnermatic Preflight

One-time setup steps. Run these **before** starting the Ralph loop.

---

## 1. Initialize the repo

```bash
cd ~/runnermatic
git init
```

Create `.gitignore`:

```
config/org.env
config/app.env
config/*.pat
config/*.pem
```

## 2. Set up config files

Copy examples if real files don't already exist:

```bash
cp -n config/org.env.example config/org.env
cp -n config/app.env.example config/app.env
```

Edit `config/org.env` — set the real PAT:

```bash
GITHUB_ORG=runnermatic
GITHUB_BASE_URL=https://github.com
GITHUB_API_URL=https://api.github.com
GITHUB_PAT=<paste your fine-grained PAT here>
```

Edit `config/app.env` — verify the pre-filled values and set the PEM path:

```bash
GITHUB_APP_PRIVATE_KEY_PATH=/home/mike/runnermatic/config/runnermatic-tokenizer.pem
```

The `GITHUB_APP_ID` and `GITHUB_APP_INSTALLATION_ID` values are pre-filled in the example. Accept them as correct.

## 3. Authenticate the gh CLI

```bash
gh auth login --with-token <<< "$(grep GITHUB_PAT config/org.env | cut -d= -f2)"
```

Verify: `gh auth status` should show the `runnermatic` org.

## 4. Create the service user

```bash
sudo useradd --system --shell /usr/sbin/nologin github-runner
```

## 5. Create runner directories and download runner binary

Create `/srv/github-runner-1` through `/srv/github-runner-4`:

```bash
sudo mkdir -p /srv/github-runner-{1,2,3,4}
```

Download and extract the latest runner:

```bash
RUNNER_URL=$(curl -sL https://api.github.com/repos/actions/runner/releases/latest \
  | jq -r '.assets[] | select(.name | test("actions-runner-linux-x64-.+\\.tar\\.gz$")) | .browser_download_url')

curl -sL "$RUNNER_URL" -o /tmp/actions-runner.tar.gz

for i in 1 2 3 4; do
  sudo tar -xzf /tmp/actions-runner.tar.gz -C /srv/github-runner-$i
done

sudo chown -R github-runner:github-runner /srv/github-runner-{1,2,3,4}
```

## 6. Verify preflight

```bash
# Git repo exists
git status

# gh authenticated
gh auth status

# Service user exists
id github-runner

# Runner dirs populated
ls /srv/github-runner-1/config.sh

# Config files in place
test -f config/org.env && echo "org.env OK"
test -f config/app.env && echo "app.env OK"
test -f config/runnermatic-tokenizer.pem && echo "PEM OK"
```

All checks pass → start the Ralph loop with `MISSION.md`.
