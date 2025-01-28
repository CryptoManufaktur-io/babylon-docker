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

echo "Initialization complete. Ready to start fpd."

sed -i 's/EOTSManagerAddress = 127.0.0.1:12582/EOTSManagerAddress = eotsd:12582/' /home/finality-provider/.fpd/fpd.conf
sleep 5000
cat /home/finality-provider/.fpd/fpd.conf

exec "$@" ${EXTRA_FLAGS}
