#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="${1:?Usage: configure-runner.sh <pat|app> <index> [labels]}"
INDEX="${2:?Usage: configure-runner.sh <pat|app> <index> [labels]}"
LABELS="${3:-self-hosted,lab}"

RUNNER_DIR="/srv/github-runner-$INDEX"
RUNNER_NAME="runnermatic-$INDEX"

if [ ! -d "$RUNNER_DIR" ]; then
  echo "ERROR: Runner directory $RUNNER_DIR does not exist" >&2
  exit 1
fi

# Skip if already configured
if [ -f "$RUNNER_DIR/.runner" ]; then
  echo "Runner $INDEX already configured, skipping."
  exit 0
fi

source "$PROJECT_ROOT/config/org.env"

# Get registration token
case "$MODE" in
  pat)
    TOKEN=$("$SCRIPT_DIR/register-runner-with-pat.sh")
    ;;
  app)
    TOKEN=$("$SCRIPT_DIR/register-runner-with-app.sh")
    ;;
  *)
    echo "ERROR: MODE must be 'pat' or 'app', got '$MODE'" >&2
    exit 1
    ;;
esac

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get registration token" >&2
  exit 1
fi

# Configure the runner
sudo -u github-runner "$RUNNER_DIR/config.sh" \
  --url "https://github.com/$GITHUB_ORG" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$LABELS" \
  --unattended
