#!/usr/bin/env bash
set -euo pipefail

STOPPED=false
REQUIRED_VARS=("MONIKER" "NETWORK" "CL_P2P_PORT" "CL_RPC_PORT")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Error: Environment variable $var is not set!" >&2
    exit 1
  fi
done

# Handle SIGTERM and SIGINT for fast shutdown
trap 'STOPPED=true; echo "Stopping services..."; pkill -SIGTERM babylond' SIGTERM SIGINT


if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  echo "Running init..."
  babylond init "$MONIKER" --chain-id "$NETWORK" --home /cosmos --overwrite --bls-password "$BLS_PASSWORD"

  echo "Downloading genesis..."
  wget https://raw.githubusercontent.com/babylonlabs-io/networks/refs/heads/main/$NETWORK/network-artifacts/genesis.json -O /cosmos/config/genesis.json

  echo "Downloading seeds..."
  SEEDS=$(curl -sL https://raw.githubusercontent.com/babylonlabs-io/networks/refs/heads/main/$NETWORK/seeds.txt | tr '\n' ',')
  [[ "$STOPPED" == "true" ]] && exit 0

  echo "Downloading peers..."
  PEERS=$(curl -sL https://raw.githubusercontent.com/babylonlabs-io/networks/refs/heads/main/$NETWORK/peers.txt | tr '\n' ',')
  [[ "$STOPPED" == "true" ]] && exit 0

  dasel put -f /cosmos/config/config.toml -v "$SEEDS" p2p.seeds
  dasel put -f /cosmos/config/config.toml -v "$PEERS" p2p.persistent_peers

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot with aria2c..."

    # Download the snapshot
    aria2c -x5 -s5 -j5 --allow-overwrite=true --console-log-level=notice --summary-interval=10 -d /cosmos -o snapshot.lz4 "$SNAPSHOT"

    if [ ! -f "/cosmos/snapshot.lz4" ]; then
      echo "Error: Snapshot file not found after download!"
      exit 1
    fi

    echo "Extracting snapshot..."
    
    # Get total snapshot size
    SNAPSHOT_SIZE=$(stat -c %s /cosmos/snapshot.lz4)

    # Use `pv` to show extraction progress
    pv -s "$SNAPSHOT_SIZE" /cosmos/snapshot.lz4 | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos

    echo "Snapshot successfully extracted!"
    rm -f /cosmos/snapshot.lz4  # Cleanup after extraction

  else
    echo "No snapshot URL defined."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

echo "Updating config..."

# Get public IP address.
__public_ip=$(curl -s ifconfig.me || curl -s http://checkip.amazonaws.com || echo "UNKNOWN")
[[ "$STOPPED" == "true" ]] && exit 0
echo "Public ip: ${__public_ip}"

# Always update public IP address, moniker, and ports.
dasel put -f /cosmos/config/config.toml -v "10s" consensus.timeout_commit
dasel put -f /cosmos/config/config.toml -v "${__public_ip}:${CL_P2P_PORT}" p2p.external_address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT}" p2p.laddr
dasel put -f /cosmos/config/config.toml -v "200" p2p.max_num_inbound_peers
dasel put -f /cosmos/config/config.toml -v "200" p2p.max_num_outbound_peers
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v "$MONIKER" moniker
dasel put -f /cosmos/config/config.toml -v true prometheus
dasel put -f /cosmos/config/config.toml -v "$LOG_LEVEL" log_level
dasel put -f /cosmos/config/config.toml -v true instrumentation.prometheus
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true grpc.enable
dasel put -f /cosmos/config/app.toml -v "$MIN_GAS_PRICE" "minimum-gas-prices"
dasel put -f /cosmos/config/app.toml -v 0 "iavl-cache-size"
dasel put -f /cosmos/config/app.toml -v "true" "iavl-disable-fastnode"
dasel put -f /cosmos/config/app.toml -v "signet" "btc-config.network"
dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node


# Enable or disable remote signer based on environment variable
REMOTE_SIGNER=${REMOTE_SIGNER:-false}

if [[ "$REMOTE_SIGNER" == "true" ]]; then
  echo "Enabling remote signer..."
  dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:26659" "priv_validator_laddr"
else
  echo "Disabling remote signer (default)..."
  dasel put -f /cosmos/config/config.toml -v "" "priv_validator_laddr"
fi

echo "Starting Babylon node..."
exec "$@"