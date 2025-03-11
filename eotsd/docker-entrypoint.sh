#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/home/finality-provider/.eotsd"
STOPPED=false

# Handle SIGTERM and SIGINT for fast shutdown
trap 'STOPPED=true' SIGTERM SIGINT

# Wait for .eotsd directory to exist
while [[ ! -d "$CONFIG_DIR" ]]; do
  echo "Waiting for initialization... ($CONFIG_DIR does not exist)"
  eotsd init
  [[ "$STOPPED" == "true" ]] && exit 0  # Exit immediately if stopping
  sleep 2
done

# Wait for keys to be imported
until eotsd keys list --keyring-backend test 2>/dev/null | grep -q "address:"; do
  echo "Waiting for keys to be imported..."
  [[ "$STOPPED" == "true" ]] && exit 0
  sleep 2
done

echo "Initialization complete. Ready to start eotsd."

# Default to "start" if no command is passed
if [[ $# -eq 0 ]]; then
  echo "No command specified. Defaulting to 'start'."
  set -- start
fi

exec "$@" ${EXTRA_FLAGS}
