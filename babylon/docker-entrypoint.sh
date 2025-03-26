#!/usr/bin/env bash
set -euo pipefail

# Common cosmovisor paths.
__cosmovisor_path=/cosmos/cosmovisor
__genesis_path=$__cosmovisor_path/genesis
__current_path=$__cosmovisor_path/current
__upgrades_path=$__cosmovisor_path/upgrades

__version_number=${DAEMON_VERSION#v}
__download_url="${DOWNLOAD_BASE_URL}/${DAEMON_VERSION}/babylon-${__version_number}-linux-amd64"

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  wget "${__download_url}" -O $__genesis_path/bin/$DAEMON_NAME
  chmod +x $__genesis_path/bin/$DAEMON_NAME

  mkdir -p $__upgrades_path/$DAEMON_VERSION/bin
  cp  $__genesis_path/bin/$DAEMON_NAME $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME

  # Point to current.
  ln -s -f $__genesis_path $__current_path

  echo "Running init..."
  $__genesis_path/bin/$DAEMON_NAME init $MONIKER --chain-id $NETWORK --home /cosmos --overwrite --bls-password $BLS_PASSWORD

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

# Handle updates and upgrades.
__should_update=0

compare_versions() {
    current=$1
    new=$2

    # Remove leading 'v' if present
    ver_current="${current#v}"
    ver_new="${new#v}"

    # Check if the versions match exactly
    if [ "$ver_current" = "$ver_new" ]; then
        __should_update=0  # Versions are the same
    else
        __should_update=1  # Versions are different
    fi
}

# First, we get the current version and compare it with the desired version.
__current_version=$($__current_path/bin/$DAEMON_NAME version 2>&1)

echo "Current version: ${__current_version}. Desired version: ${DAEMON_VERSION}"

compare_versions $__current_version $DAEMON_VERSION

if [ "$__should_update" -eq 1 ]; then
  echo "Downloading new version and setting it as current"
  mkdir -p $__upgrades_path/$DAEMON_VERSION/bin
  wget "${__download_url}" -O $__upgrades_path/$DAEMON_VERSION/bin/$DAEMON_NAME
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
dasel put -f /cosmos/config/app.toml -v "signet" "btc-config.network"
dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node

# Start the process in a new session, so it gets its own process group.
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
setsid "$@" ${EXTRA_FLAGS} &
pid=$!

# Trap SIGTERM in the script and forward it to the process group
trap 'kill -TERM -$pid' TERM

# Wait for the background process to complete
wait $pid
