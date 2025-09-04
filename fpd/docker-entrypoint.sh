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
sed -i 's/^BatchSubmissionSize[[:space:]]*=[[:space:]]*.*/BatchSubmissionSize = 250/' /data/fpd/fpd.conf
sed -i 's/^BufferSize[[:space:]]*=[[:space:]]*.*/BufferSize = 10000/' /data/fpd/fpd.conf
sed -i 's/^PollInterval[[:space:]]*=[[:space:]]*.*/PollInterval = 200ms/' /data/fpd/fpd.conf

if sed -n '/\[chainpollerconfig\]/,/^\[/p' /data/fpd/fpd.conf | grep -q 'PollSize'; then
  # Update the existing PollSize value
  sed -i '/\[chainpollerconfig\]/,/\[/ s/^\(\s*PollSize\s*=\s*\).*/\1 20/' /data/fpd/fpd.conf
else
  # Append PollSize after BufferSize if PollSize is not present
  sed -i '/BufferSize = 10000/a PollSize = 20' /data/fpd/fpd.conf
fi

# Add GRPCMaxContentLength and UnsafeResetLastVotedHeight if not present
if grep -q '^GRPCMaxContentLength' /data/fpd/fpd.conf; then
  sed -i 's/^GRPCMaxContentLength[[:space:]]*=[[:space:]]*.*/GRPCMaxContentLength = 16777216/' /data/fpd/fpd.conf
  sed -i 's/^UnsafeResetLastVotedHeight[[:space:]]*=[[:space:]]*.*/UnsafeResetLastVotedHeight = true/' /data/fpd/fpd.conf
else
  cat <<EOF >> /data/fpd/fpd.conf
[Application Options]
; The maximum size of the gRPC message in bytes.
GRPCMaxContentLength = 16777216

; WARNING: If set to 'true', resets the finality provider's last voted height to the calculated start height from poller. WARNING
UnsafeResetLastVotedHeight = true
EOF
fi


# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
