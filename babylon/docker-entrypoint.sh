#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# Babylon Node Docker Entrypoint Script
#############################################################################
# This script initializes and starts a Babylon node with cosmovisor.
#
# Improvements for fast startup:
# - Retry logic with exponential backoff for network operations
# - Progress bars for large downloads (snapshots)
# - Genesis file validation (JSON check)
# - Public IP detection with fallback services
# - Graceful error handling for non-critical operations
# - Support for multiple snapshot formats (.tar.lz4, .tar.gz, .tar)
# - Validation checks after initialization
#
# Cosmovisor structure:
# - /cosmos/cosmovisor/genesis/bin/     - Genesis binary
# - /cosmos/cosmovisor/current/         - Symlink to current version
# - /cosmos/cosmovisor/upgrades/        - Upgrade binaries by version
#############################################################################

# Function for retrying commands with exponential backoff
retry_with_backoff() {
  local max_attempts=5
  local timeout=1
  local attempt=1
  local exitCode=0

  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    else
      exitCode=$?
    fi

    if [ $attempt -lt $max_attempts ]; then
      echo "Attempt $attempt failed. Retrying in $timeout seconds..." >&2
      sleep $timeout
      timeout=$((timeout * 2))
    fi

    attempt=$((attempt + 1))
  done

  echo "Command failed after $max_attempts attempts." >&2
  return $exitCode
}

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
  if [ "$NETWORK" = "bbn-1" ]; then
    retry_with_backoff wget -O /cosmos/config/genesis.json https://snapshots.polkachu.com/genesis/babylon/genesis.json --inet4-only --timeout=30 --tries=3 --continue
  else
    retry_with_backoff wget -O /cosmos/config/genesis.json https://snapshots.polkachu.com/testnet-genesis/babylon/genesis.json --inet4-only --timeout=30 --tries=3 --continue
  fi

  # Verify genesis file is valid JSON
  if ! jq empty /cosmos/config/genesis.json 2>/dev/null; then
    echo "Error: Downloaded genesis file is not valid JSON"
    exit 1
  fi
  echo "Genesis file downloaded and verified successfully"

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot from: $SNAPSHOT"
    echo "This may take a while depending on your connection speed..."

    # Use parallel decompression for faster extraction
    if [[ "$SNAPSHOT" == *.tar.lz4 ]]; then
      echo "Detected lz4 compressed snapshot"
      retry_with_backoff curl -L --progress-bar --max-time 7200 "$SNAPSHOT" | lz4 -d -c | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
    elif [[ "$SNAPSHOT" == *.tar.gz ]]; then
      echo "Detected gzip compressed snapshot"
      retry_with_backoff curl -L --progress-bar --max-time 7200 "$SNAPSHOT" | tar --exclude='data/priv_validator_state.json' -xzf - -C /cosmos
    elif [[ "$SNAPSHOT" == *.tar ]]; then
      echo "Detected uncompressed tar snapshot"
      retry_with_backoff curl -L --progress-bar --max-time 7200 "$SNAPSHOT" | tar --exclude='data/priv_validator_state.json' -xf - -C /cosmos
    else
      echo "Error: Unsupported snapshot format: $SNAPSHOT"
      echo "Supported formats: .tar.lz4, .tar.gz, .tar"
      exit 1
    fi

    # Clean up any upgrade info from snapshot
    rm -f /cosmos/data/upgrade-info.json

    echo "Snapshot extraction completed successfully"
  else
    echo "No snapshot URL defined. Starting from genesis (this will take longer to sync)."
  fi

  # Validate initialization
  echo "Validating initialization..."
  if [ ! -f /cosmos/config/genesis.json ]; then
    echo "Error: Genesis file missing after initialization"
    exit 1
  fi

  if [ ! -f /cosmos/config/config.toml ]; then
    echo "Error: Config file missing after initialization"
    exit 1
  fi

  if [ ! -x $__current_path/bin/$DAEMON_NAME ]; then
    echo "Error: Daemon binary not found or not executable"
    exit 1
  fi

  echo "Initialization validation passed"
  touch /cosmos/.initialized
else
  echo "Already initialized!"

  # Quick validation that critical files exist
  if [ ! -f /cosmos/config/genesis.json ] || [ ! -f /cosmos/config/config.toml ]; then
    echo "Warning: Missing critical configuration files. Re-initialization may be needed."
    echo "Consider removing /cosmos/.initialized and restarting to re-initialize."
  fi
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

# Get public IP address with retry and fallback
echo "Detecting public IP address..."
if __public_ip=$(retry_with_backoff curl -s --max-time 10 ifconfig.me/ip); then
  if [[ "$__public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Public IP detected: ${__public_ip}"
  else
    echo "Warning: Invalid IP format from ifconfig.me, trying alternative service..."
    if __public_ip=$(retry_with_backoff curl -s --max-time 10 icanhazip.com); then
      echo "Public IP detected: ${__public_ip}"
    else
      echo "Warning: Could not detect public IP, using 0.0.0.0"
      __public_ip="0.0.0.0"
    fi
  fi
else
  echo "Warning: Could not detect public IP, using 0.0.0.0"
  __public_ip="0.0.0.0"
fi

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
dasel put -f /cosmos/config/app.toml -v "tcp://0.0.0.0:${CL_REST_PORT}" api.address
dasel put -f /cosmos/config/app.toml -t bool -v true api.enable
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


# Start the process in a new session, so it gets its own process group.
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
setsid "$@" ${EXTRA_FLAGS} &
pid=$!

# Trap SIGTERM in the script and forward it to the process group
trap 'kill -TERM -$pid' TERM

# Wait for the background process to complete
wait $pid
