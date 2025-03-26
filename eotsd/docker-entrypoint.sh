#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/home/finality-provider/.eotsd"

# Initialize
if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "Running init..."
  eotsd init
fi

echo "Initialization complete. Ready to start eotsd."

sed -i '/^\[metrics\]/,/^\[/{ /^[^[]/ s/127\.0\.0\.1/0.0.0.0/g }' /home/finality-provider/.eotsd/eotsd.conf

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
