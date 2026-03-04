#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

UNIT_FILE="$PROJECT_ROOT/systemd/github-runner@.service"
SYSTEMD_DIR="/etc/systemd/system"

usage() {
  echo "Usage: manage-runners.sh <command> [args]"
  echo "Commands:"
  echo "  install-unit    Copy systemd unit and reload daemon"
  echo "  start <N>       Start runner N"
  echo "  stop <N>        Stop runner N"
  echo "  start-all       Start runners 1-4"
  echo "  stop-all        Stop runners 1-4"
  echo "  status          Show status of all runners"
  exit 1
}

CMD="${1:-}"
[ -z "$CMD" ] && usage

case "$CMD" in
  install-unit)
    sudo cp "$UNIT_FILE" "$SYSTEMD_DIR/"
    sudo systemctl daemon-reload
    echo "Unit installed and daemon reloaded."
    ;;
  start)
    N="${2:?Usage: manage-runners.sh start <N>}"
    sudo systemctl start "github-runner@${N}.service"
    echo "Runner $N started."
    ;;
  stop)
    N="${2:?Usage: manage-runners.sh stop <N>}"
    sudo systemctl stop "github-runner@${N}.service"
    echo "Runner $N stopped."
    ;;
  start-all)
    for i in 1 2 3 4; do
      sudo systemctl start "github-runner@${i}.service"
      echo "Runner $i started."
    done
    ;;
  stop-all)
    for i in 1 2 3 4; do
      sudo systemctl stop "github-runner@${i}.service"
      echo "Runner $i stopped."
    done
    ;;
  status)
    for i in 1 2 3 4; do
      echo "--- Runner $i ---"
      sudo systemctl status "github-runner@${i}.service" --no-pager || true
    done
    ;;
  *)
    usage
    ;;
esac
