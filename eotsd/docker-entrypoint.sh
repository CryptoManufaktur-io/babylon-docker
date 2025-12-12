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

# Add NoFreelistSync if not present
if grep -q '^NoFreelistSync' /data/eotsd/eotsd.conf; then
  # Update existing NoFreelistSync value to false
  sed -i 's/^NoFreelistSync[[:space:]]*=[[:space:]]*.*/NoFreelistSync = false/' /data/eotsd/eotsd.conf
else
  cat <<EOF >> /data/eotsd/eotsd.conf
[dbconfig]
NoFreelistSync = false
EOF
fi

# Add or update DisableUnsafeEndpoints under [Application Options]
if grep -q '^\[Application Options\]' /data/eotsd/eotsd.conf; then
  # Section exists, check if DisableUnsafeEndpoints is present
  if grep -q '^DisableUnsafeEndpoints' /data/eotsd/eotsd.conf; then
    # Update existing value
    sed -i 's/^DisableUnsafeEndpoints[[:space:]]*=[[:space:]]*.*/DisableUnsafeEndpoints = true/' /data/eotsd/eotsd.conf
  else
    # Add it after the [Application Options] line
    sed -i '/^\[Application Options\]/a DisableUnsafeEndpoints = true' /data/eotsd/eotsd.conf
  fi
fi

# Update HMACKey value
if grep -q '^HMACKey' /data/eotsd/eotsd.conf; then
  sed -i "s|^HMACKey[[:space:]]*=[[:space:]]*.*|HMACKey = ${HMAC_KEY}|" /data/eotsd/eotsd.conf
fi

if [ "$NETWORK" = "bbn-test-5" ]; then
  # Add GRPCMaxContentLength if not present
  if grep -q '^GRPCMaxContentLength' /data/eotsd/eotsd.conf; then
    # Update existing GRPCMaxContentLength value to 16777216
    sed -i 's/^GRPCMaxContentLength[[:space:]]*=[[:space:]]*.*/GRPCMaxContentLength = 16777216/' /data/eotsd/eotsd.conf
  else
    cat <<EOF >> /data/eotsd/eotsd.conf
[Application Options]
; The maximum size of the gRPC message in bytes.
GRPCMaxContentLength = 16777216
EOF
  fi
fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
