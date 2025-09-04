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
# Add GRPCMaxContentLength if not present
if ! grep -q '^GRPCMaxContentLength' /data/eotsd/eotsd.conf; then
  cat <<EOF >> /data/eotsd/eotsd.conf
[Application Options]
; The maximum size of the gRPC message in bytes.
GRPCMaxContentLength = 16777216
EOF
else
  # Update existing GRPCMaxContentLength value to 16777216
  sed -i 's/^GRPCMaxContentLength[[:space:]]*=[[:space:]]*.*/GRPCMaxContentLength = 16777216/' /data/eotsd/eotsd.conf
fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
