#!/usr/bin/env bash
set -euo pipefail

# Initialize
if [[ ! -f /data/.initialized ]]; then
  echo "Running init..."
  fpd init --home /data/fpd
  mkdir -p /data/fpd/keyring-test
  fpd keys add finality-provider --home /data/fpd > /data/fpd/keyring-test/finality-provider.backup 2>&1
  touch /data/.initialized
fi

echo "Updating config..."

sed -i "s|^EOTSManagerAddress = .*|EOTSManagerAddress = ${EOTSD_HOST}|" /data/fpd/fpd.conf
sed -i "s|^RPCAddr = .*|RPCAddr = ${BABYLOND_HOST}|" /data/fpd/fpd.conf
sed -i "s|^ChainID = .*|ChainID = ${NETWORK}|" /data/fpd/fpd.conf
sed -i '/^\[metrics\]/,/^\[/{ /^[^[]/ s/127\.0\.0\.1/0.0.0.0/g }' /data/fpd/fpd.conf
# sed -i 's/^\(\s*BatchSubmissionSize\s*=\s*\).*/\1 100/' /data/fpd/fpd.conf
sed -i 's/^\(\s*BatchSubmissionSize\s*=\s*\).*/\1 250/' /data/fpd/fpd.conf
sed -i 's/^\(\s*BufferSize\s*=\s*\).*/\1 10000/' /data/fpd/fpd.conf
sed -i 's/^\(\s*PollInterval\s*=\s*\).*/\1 200ms/' /data/fpd/fpd.conf

if sed -n '/\[chainpollerconfig\]/,/^\[/p' /data/fpd/fpd.conf | grep -q 'PollSize'; then
  # Update the existing PollSize value
  sed -i '/\[chainpollerconfig\]/,/\[/ s/^\(\s*PollSize\s*=\s*\).*/\1 20/' /data/fpd/fpd.conf
else
  # Append PollSize after BufferSize if PollSize is not present
  sed -i '/BufferSize = 10000/a PollSize = 20' /data/fpd/fpd.conf
fi

# Add GRPCMaxContentLength and UnsafeResetLastVotedHeight if not present
if ! grep -q '^GRPCMaxContentLength' /data/fpd/fpd.conf; then
  cat <<EOF >> /data/fpd/fpd.conf
[Application Options]
; The maximum size of the gRPC message in bytes.
GRPCMaxContentLength = 16777216

; WARNING: If set to 'true', resets the finality provider's last voted height to the calculated start height from poller. WARNING
UnsafeResetLastVotedHeight = true
EOF
else
  # Update existing GRPCMaxContentLength value to 16777216 and UnsafeResetLastVotedHeight to true
  sed -i 's/^\(\s*GRPCMaxContentLength\s*=\s*\).*/\1 16777216/' /data/fpd/fpd.conf
  sed -i 's/^\(\s*UnsafeResetLastVotedHeight\s*=\s*\).*/\1 true/' /data/fpd/fpd.conf
fi


# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
