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
sed -i 's/^\(\s*BatchSubmissionSize\s*=\s*\).*/\1 100/' /data/fpd/fpd.conf

if sed -n '/\[chainpollerconfig\]/,/^\[/p' /data/fpd/fpd.conf | grep -q 'PollSize'; then
  # Update the existing PollSize value
  sed -i '/\[chainpollerconfig\]/,/\[/ s/^\(\s*PollSize\s*=\s*\).*/\1 100/' /data/fpd/fpd.conf
else
  # Append PollSize after BufferSize if PollSize is not present
  sed -i '/BufferSize = 1000/a PollSize = 100' /data/fpd/fpd.conf
fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
