#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/home/finality-provider/.fpd"

# Wait for .fpd directory to exist
while [[ ! -d "$CONFIG_DIR" ]]; do
  echo "Waiting for initialization... ($CONFIG_DIR does not exist)"
  fpd init
done

# Wait for keys to be imported
until fpd keys list 2>/dev/null | jq -e '.[] | .address' >/dev/null; do
  echo "Waiting for keys to be imported..."
  sleep 2
done

echo "Waiting for Babylon node to finish syncing..."
while [[ $(curl -s http://${RPC_HOST}:${CL_RPC_PORT}/status | jq -r .result.sync_info.catching_up) == "true" ]]; do
  echo "Babylon node is still catching up... waiting..."
  sleep 2
done

echo "Ensuring Config updates have been applied"

sed -i "s/EOTSManagerAddress = 127.0.0.1:12582/EOTSManagerAddress = eotsd:${EOTSD_LISTENER_PORT}/" /home/finality-provider/.fpd/fpd.conf
sed -i "s|RPCAddr = http://localhost:26657|RPCAddr = http://${RPC_HOST}:${CL_RPC_PORT}|" /home/finality-provider/.fpd/fpd.conf
sed -i "s|^ChainID = .*|ChainID = ${NETWORK}|" /home/finality-provider/.fpd/fpd.conf
sed -i '/^\[metrics\]/,/^\[/{ /^[^[]/ s/127\.0\.0\.1/0.0.0.0/g }' /home/finality-provider/.fpd/fpd.conf

echo "Starting fpd..."

exec "$@" ${EXTRA_FLAGS}
