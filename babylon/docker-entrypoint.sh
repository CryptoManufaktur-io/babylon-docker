#!/usr/bin/env bash
set -euo pipefail

# Common cosmovisor paths.
__cosmovisor_path=/cosmos/cosmovisor
__genesis_path=$__cosmovisor_path/genesis
__current_path=$__cosmovisor_path/current
__upgrades_path=$__cosmovisor_path/upgrades

__version_number=${DAEMON_VERSION#v}

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  cp /builds/babylond-${DAEMON_VERSION} $__genesis_path/bin/$DAEMON_NAME
  chmod +x $__genesis_path/bin/$DAEMON_NAME

  mkdir -p $__upgrades_path/$DAEMON_VERSION/bin
  cp  $__genesis_path/bin/$DAEMON_NAME $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME

  # Point to current.
  ln -s -f $__genesis_path $__current_path

  echo "Running init..."
  $__genesis_path/bin/$DAEMON_NAME init $MONIKER --chain-id $NETWORK --home /cosmos --overwrite

  echo "Downloading genesis..."
  wget https://raw.githubusercontent.com/galaxy-mario/babylon-networks/refs/heads/main/$NETWORK/network-artifacts/genesis.json -O /cosmos/config/genesis.json

  echo "Downloading seeds..."
  SEEDS=$(curl -sL https://raw.githubusercontent.com/galaxy-mario/babylon-networks/refs/heads/main/$NETWORK/network-artifacts/seeds.txt | tr '\n' ',')
  dasel put -f /cosmos/config/config.toml -v "$SEEDS" p2p.seeds

  if [ -n "$SNAPSHOT" ]; then
  echo "Downloading snapshot..."
    if [[ "$SNAPSHOT" == *.tar.lz4 ]]; then
      curl -o - -L "$SNAPSHOT" | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
    elif [[ "$SNAPSHOT" == *.tar.gz ]]; then
      curl -o - -L "$SNAPSHOT" | tar --exclude='data/priv_validator_state.json' -xzvf - -C /cosmos
    else
      echo "Unsupported snapshot format: $SNAPSHOT"
      exit 1
    fi
    rm -f /cosmos/data/upgrade-info.json
  else
    echo "No snapshot URL defined."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

# Handle updates.
__different_version=0

compare_versions() {
    current=$1
    new=$2

    # Remove leading 'v' if present
    ver_current="${current#v}"
    ver_new="${new#v}"

    # Check if the versions match exactly
    if [ "$ver_current" = "$ver_new" ]; then
        __different_version=0  # Versions are the same
    else
        __different_version=1  # Versions are different
    fi
}

# First, we get the current version and compare it with the desired version.
__current_version=$($__current_path/bin/$DAEMON_NAME version 2>&1)

echo "Current version: ${__current_version}. Desired version: ${DAEMON_VERSION}"

compare_versions $__current_version $DAEMON_VERSION

if [ "$__different_version" -eq 1 ] && [ "$FORCE_UPDATE" = "true" ]; then
  echo "Copying new version and setting it as current"
  mkdir -p $__upgrades_path/$DAEMON_VERSION/bin
  cp /builds/babylond-${DAEMON_VERSION} $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME
  chmod +x $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME
  rm -f $__current_path
  ln -s -f $__upgrades_path/$DAEMON_VERSION $__current_path
  echo "Done!"
else
  echo "No updates needed."
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
dasel put -f /cosmos/config/config.toml -v true instrumentation.prometheus

dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true grpc.enable
dasel put -f /cosmos/config/app.toml -v "${MIN_GAS_PRICE}" "minimum-gas-prices"
dasel put -f /cosmos/config/app.toml -v 0 "iavl-cache-size"
dasel put -f /cosmos/config/app.toml -v "true" "iavl-disable-fastnode"
dasel put -f /cosmos/config/app.toml -v 0 mempool.max-txs

if [ "$NETWORK" = "bbn-1" ]; then
  dasel put -f /cosmos/config/config.toml -v "9200ms" consensus.timeout_commit
  dasel put -f /cosmos/config/app.toml -v "mainnet" "btc-config.network"
else
  dasel put -f /cosmos/config/config.toml -v "10s" consensus.timeout_commit
  dasel put -f /cosmos/config/app.toml -v "signet" "btc-config.network"
fi

dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node

echo "Downloading peers..."
PEERS=$(curl -sL https://raw.githubusercontent.com/galaxy-mario/babylon-networks/refs/heads/main/$NETWORK/network-artifacts/peers.txt | tr '\n' ',')
dasel put -f /cosmos/config/config.toml -v "$PEERS" p2p.persistent_peers

# Start the process in a new session, so it gets its own process group.
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
setsid "$@" ${EXTRA_FLAGS} &
pid=$!

# Trap SIGTERM in the script and forward it to the process group
trap 'kill -TERM -$pid' TERM

# Wait for the background process to complete
wait $pid
