#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/home/finality-provider/.eotsd"

# Initialize
if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "Initializing since $CONFIG_DIR does not exist"
  eotsd init
fi

# Wait for keys to be imported
until eotsd keys list --keyring-backend test 2>/dev/null | grep -q "address:"; do
  echo "Waiting for keys to be imported..."
  sleep 2
done

echo "Initialization complete. Ready to start eotsd."

# sleep infinity

# Default to "start" if no command is passed
if [[ $# -eq 0 ]]; then
  echo "No command specified. Defaulting to 'start'."
  set -- start
fi

sed -i '/^\[metrics\]/,/^\[/{ /^[^[]/ s/127\.0\.0\.1/0.0.0.0/g }' /home/finality-provider/.eotsd/eotsd.conf

exec "$@" ${EXTRA_FLAGS}

