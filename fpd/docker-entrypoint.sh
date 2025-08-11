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

if ! sed -n '/^\[Application Options\]/,/^\[/{ /^NumPubRandMax =/p }' /data/fpd/fpd.conf | grep -q .; then
  sed -i '/^\[Application Options\]/a NumPubRandMax = 500000' /data/fpd/fpd.conf
fi

if ! sed -n '/^\[Application Options\]/,/^\[/{ /^RandomnessCommitInterval =/p }' /data/fpd/fpd.conf | grep -q .; then
  sed -i '/^\[Application Options\]/a RandomnessCommitInterval = 30s' /data/fpd/fpd.conf
fi

if ! sed -n '/^\[Application Options\]/,/^\[/{ /^ContextSigningHeight =/p }' /data/fpd/fpd.conf | grep -q .; then
  sed -i '/^\[Application Options\]/a ContextSigningHeight = 1692199' /data/fpd/fpd.conf
fi

sed -i '/^\[Application Options\]/,/^\[/{ /^[[:space:]]*ChainType = babylon/d }' /data/fpd/fpd.conf

sed -i '/^\[Application Options\]/,/^\[/{ /^[[:space:]]*BitcoinNetwork = signet/d }' /data/fpd/fpd.conf

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
