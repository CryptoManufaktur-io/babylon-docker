#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/home/finality-provider/.fpd"

# Wait for .fpd directory to exist
while [[ ! -d "$CONFIG_DIR" ]]; do
  echo "Waiting for initialization... ($CONFIG_DIR does not exist)"
  sleep 2
done

# Wait for keys to be imported
until fpd keys list 2>/dev/null | jq -e '.[] | .address' >/dev/null; do
  echo "Waiting for keys to be imported..."
  sleep 2
done

echo "Initialization complete."
sleep 50000

# Default to "start" if no command is passed
if [[ $# -eq 0 ]]; then
  echo "No command specified. Defaulting to 'start'."
  set -- start
fi

COMMAND=$1
shift # Remove the command from the arguments

# Command handling logic
case "$COMMAND" in
  start)
    echo "Keys found. Starting fpd with extra flags: ${EXTRA_FLAGS:-} $*"
    exec fpd start ${EXTRA_FLAGS:-} "$@"
    ;;
  *)
    echo "Error: Unknown command '$COMMAND'. Supported commands: start"
    exit 1
    ;;
esac
