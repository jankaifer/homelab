#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_PATH="$SCRIPT_DIR/energy-scheduler-demo.json"
STATE_DIR="/tmp/energy-scheduler-demo"
HOST="127.0.0.1"
PORT="8787"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/nix-cache-ui}"
KEEP_STATE=0

usage() {
    cat <<EOF
Usage: ./scripts/run-energy-ui-demo.sh [--host HOST] [--port PORT] [--config PATH] [--keep-state]

Starts the Energy Scheduler demo UI locally using the Bun dashboard backend.

Defaults:
  host:   127.0.0.1
  port:   8787
  config: ./scripts/energy-scheduler-demo.json

Example:
  ./scripts/run-energy-ui-demo.sh
  ./scripts/run-energy-ui-demo.sh --port 8790
  ./scripts/run-energy-ui-demo.sh --keep-state
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --keep-state)
            KEEP_STATE=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$KEEP_STATE" != "1" ]]; then
    rm -rf "$STATE_DIR"
fi

mkdir -p "$STATE_DIR" "$XDG_CACHE_HOME"

echo "Energy Scheduler demo UI"
echo "  project: $PROJECT_DIR"
echo "  config:  $CONFIG_PATH"
echo "  state:   $STATE_DIR"
echo "  reset:   $([[ \"$KEEP_STATE\" == \"1\" ]] && echo \"no\" || echo \"yes\")"
echo "  url:     http://$HOST:$PORT/"
echo ""

cd "$PROJECT_DIR"

nix develop -c env PYTHONPATH="$PROJECT_DIR/src" python -m energy_scheduler.cli \
    --config "$CONFIG_PATH" \
    --once >/dev/null

exec env ENERGY_UI_APP_JS="$PROJECT_DIR/src/energy_scheduler/ui_static/app.js" bun "$PROJECT_DIR/frontend/energy-ui-charts/src/server.ts" \
    --config "$CONFIG_PATH" \
    --host "$HOST" \
    --port "$PORT"
