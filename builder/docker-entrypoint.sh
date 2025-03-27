#!/usr/bin/env bash
set -euo pipefail

if [ ! -e "/builds/babylond-${DAEMON_VERSION}" ] || [ "$FORCE_REBUILD" = "true" ]; then
    echo "Compiling $DAEMON_VERSION binary..."

    # Always start from a clean state.
    rm -rf /src/*

    git clone https://github.com/babylonlabs-io/babylon.git && cd babylon && git checkout ${DAEMON_VERSION}

    go mod download

    # libwasm
    WASMVM_VERSION=$(go list -m github.com/CosmWasm/wasmvm/v2 | cut -d ' ' -f 2)
    wget -q https://github.com/CosmWasm/wasmvm/releases/download/$WASMVM_VERSION/libwasmvm_muslc."$(uname -m)".a \
    -O /lib/libwasmvm_muslc."$(uname -m)".a

    # verify checksum
    wget -q https://github.com/CosmWasm/wasmvm/releases/download/"$WASMVM_VERSION"/checksums.txt -O /tmp/checksums.txt
    sha256sum /lib/libwasmvm_muslc."$(uname -m)".a | grep $(cat /tmp/checksums.txt | grep libwasmvm_muslc."$(uname -m)" | cut -d ' ' -f 1)

    LEDGER_ENABLED=false BUILD_TAGS=muslc LINK_STATICALLY=true make install

    mv /go/bin/babylond /builds/babylond-${DAEMON_VERSION}

    echo "Done!"
else
    echo "No building needed!"
fi
