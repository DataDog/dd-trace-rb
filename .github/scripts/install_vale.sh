#!/bin/bash
set -euo pipefail

# Downloads and installs the pinned vale binary used by the changelog checks.

if [[ -z "${VALE_VERSION:-}" ]]; then
    echo "Error: VALE_VERSION environment variable is not set"
    exit 1
fi

if [[ -z "${VALE_SHA256:-}" ]]; then
    echo "Error: VALE_SHA256 environment variable is not set"
    exit 1
fi

archive="/tmp/vale.tar.gz"
curl -sSL -o "${archive}" \
    "https://github.com/vale-cli/vale/releases/download/v${VALE_VERSION}/vale_${VALE_VERSION}_Linux_64-bit.tar.gz"
echo "${VALE_SHA256}  ${archive}" | sha256sum -c -
tar -xzf "${archive}" -C /tmp vale
install /tmp/vale /usr/local/bin/vale
vale --version
