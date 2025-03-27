#!/usr/bin/env bash
set -euo pipefail

# Initialize
if [[ ! -f /data/.initialized ]]; then
  echo "Running init..."
  eotsd init --home /data/eotsd
  touch /data/.initialized
fi

echo "Initialization complete. Ready to start eotsd."

sed -i '/^\[metrics\]/,/^\[/{ /^[^[]/ s/127\.0\.0\.1/0.0.0.0/g }' /data/eotsd/eotsd.conf

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
