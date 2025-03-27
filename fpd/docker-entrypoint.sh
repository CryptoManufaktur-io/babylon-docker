#!/usr/bin/env bash
set -euo pipefail

# Initialize
if [[ ! -f /data/.initialized ]]; then
  echo "Running init..."
  fpd init --home /data/fpd
  touch /data/.initialized
fi

echo "Updating config..."

sed -i "s/EOTSManagerAddress = 127.0.0.1:12582/EOTSManagerAddress = eotsd:${EOTSD_PORT}/" /data/fpd/fpd.conf
sed -i "s|RPCAddr = http://localhost:26657|RPCAddr = http://${RPC_HOST}:${CL_RPC_PORT}|" /data/fpd/fpd.conf
sed -i "s|^ChainID = .*|ChainID = ${NETWORK}|" /data/fpd/fpd.conf
sed -i '/^\[metrics\]/,/^\[/{ /^[^[]/ s/127\.0\.0\.1/0.0.0.0/g }' /data/fpd/fpd.conf

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
