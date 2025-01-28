#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/home/finality-provider/.eotsd"

# Wait for .eotsd directory to exist
while [[ ! -d "$CONFIG_DIR" ]]; do
  echo "Waiting for initialization... ($CONFIG_DIR does not exist)"
  sleep 2
done

# Wait for keys to be imported
until eotsd keys list --keyring-backend test 2>/dev/null | grep -q "address:"; do
  echo "Waiting for keys to be imported..."
  sleep 2
done

echo "Initialization complete. Ready to start eotsd."

# Default to "start" if no command is passed
if [[ $# -eq 0 ]]; then
  echo "No command specified. Defaulting to 'start'."
  set -- start
fi

exec "$@" ${EXTRA_FLAGS}

# COMMAND=$1
# shift # Remove the command from the arguments

# # Command handling logic
# case "$COMMAND" in
#   start)
#     echo "Keys found. Starting eotsd with --rpc-listener: ${EOTSD_LISTENER}"
#     exec eotsd start --rpc-listener "${EOTSD_LISTENER}" ${EXTRA_FLAGS:-} "$@"
#     ;;
#   *)
#     echo "Error: Unknown command '$COMMAND'. Supported commands: start"
#     exit 1
#     ;;
# esac
