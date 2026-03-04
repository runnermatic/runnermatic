#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config/org.env"

gh api --method POST "/orgs/$GITHUB_ORG/actions/runners/registration-token" --jq '.token'
