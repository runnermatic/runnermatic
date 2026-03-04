#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config/app.env"
export GITHUB_APP_ID GITHUB_APP_PRIVATE_KEY_PATH

# Generate JWT from App credentials
JWT=$("$SCRIPT_DIR/generate-jwt.js")

# Get installation access token
INSTALL_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens" \
  | jq -r '.token')

if [ -z "$INSTALL_TOKEN" ] || [ "$INSTALL_TOKEN" = "null" ]; then
  echo "ERROR: Failed to get installation access token" >&2
  exit 1
fi

# Get runner registration token using installation token
curl -s -X POST \
  -H "Authorization: Bearer $INSTALL_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/orgs/$GITHUB_ORG/actions/runners/registration-token" \
  | jq -r '.token'
