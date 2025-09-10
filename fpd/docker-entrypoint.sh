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

# Testnet only changes from hotfix
if [ "$NETWORK" = "bbn-test-5" ]; then
  sed -i 's/^BatchSubmissionSize[[:space:]]*=[[:space:]]*.*/BatchSubmissionSize = 1000/' /data/fpd/fpd.conf
  sed -i 's/^BufferSize[[:space:]]*=[[:space:]]*.*/BufferSize = 1000/' /data/fpd/fpd.conf
  sed -i 's/^PollInterval[[:space:]]*=[[:space:]]*.*/PollInterval = 1s/' /data/fpd/fpd.conf
  sed -i 's/^TimestampingDelayBlocks[[:space:]]*=[[:space:]]*.*/TimestampingDelayBlocks = 80000/' /data/fpd/fpd.conf
  sed -i 's/^NumPubRand[[:space:]]*=[[:space:]]*.*/NumPubRand = 160000/' /data/fpd/fpd.conf
  # this removes an old testnet value that we no longer need
  sed -i '/^UnsafeResetLastVotedHeight[[:space:]]*=[[:space:]]*true$/d' /data/fpd/fpd.conf

  if sed -n '/\[chainpollerconfig\]/,/^\[/p' /data/fpd/fpd.conf | grep -q 'PollSize'; then
    # Update the existing PollSize value
    sed -i '/\[chainpollerconfig\]/,/\[/ s/^\(\s*PollSize\s*=\s*\).*/\1 1000/' /data/fpd/fpd.conf
  else
    # Append PollSize after BufferSize if PollSize is not present
    sed -i '/BufferSize = 1000/a PollSize = 1000' /data/fpd/fpd.conf
  fi

  # Add GRPCMaxContentLength and UnsafeResetLastVotedHeight if not present
  if grep -q '^GRPCMaxContentLength' /data/fpd/fpd.conf; then
    sed -i 's/^GRPCMaxContentLength[[:space:]]*=[[:space:]]*.*/GRPCMaxContentLength = 16777216/' /data/fpd/fpd.conf

  else
    cat <<EOF >> /data/fpd/fpd.conf
[Application Options]
; The maximum size of the gRPC message in bytes.
GRPCMaxContentLength = 16777216
EOF
  fi
fi


# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
