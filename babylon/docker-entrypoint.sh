#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  echo "Running init..."
  babylond init $MONIKER --chain-id $NETWORK --home /cosmos --overwrite

  echo "Downloading genesis..."
  wget https://raw.githubusercontent.com/babylonlabs-io/networks/refs/heads/main/$NETWORK/network-artifacts/genesis.json -O /cosmos/config/genesis.json

  echo "Downloading seeds..."
  SEEDS=$(curl -sL https://raw.githubusercontent.com/babylonlabs-io/networks/refs/heads/main/$NETWORK/seeds.txt | tr '\n' ',')
  
  echo "Downloading peers..."
  PEERS=$(curl -sL https://raw.githubusercontent.com/babylonlabs-io/networks/refs/heads/main/$NETWORK/peers.txt | tr '\n' ',')

  dasel put -f /cosmos/config/config.toml -v $SEEDS p2p.seeds
  dasel put -f /cosmos/config/config.toml -v $PEERS p2p.persistent_peers

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot..."
    curl -o - -L $SNAPSHOT | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
  else
    echo "No snapshot URL defined."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

echo "Updating config..."

# Get public IP address.
__public_ip=$(curl -s ifconfig.me/ip)
echo "Public ip: ${__public_ip}"

# Always update public IP address, moniker and ports.
dasel put -f /cosmos/config/config.toml -v "10s" consensus.timeout_commit
dasel put -f /cosmos/config/config.toml -v "${__public_ip}:${CL_P2P_PORT}" p2p.external_address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT}" p2p.laddr
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v ${MONIKER} moniker
dasel put -f /cosmos/config/config.toml -v true prometheus
dasel put -f /cosmos/config/config.toml -v ${LOG_LEVEL} log_level
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true grpc.enable
dasel put -f /cosmos/config/app.toml -v "${MIN_GAS_PRICE}" "minimum-gas-prices"
dasel put -f /cosmos/config/app.toml -v 0 "iavl-cache-size"
dasel put -f /cosmos/config/app.toml -v "true" "iavl-disable-fastnode"
dasel put -f /cosmos/config/app.toml -v "signet" "btc-config.network"
dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}