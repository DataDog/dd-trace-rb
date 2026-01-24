#!/usr/bin/env bash
# Helper script to run act with cache support enabled
#
# Usage:
#   ./scripts/act-with-cache.sh                    # Run default workflow
#   ./scripts/act-with-cache.sh -W .github/workflows/test.yml -j ruby-34
#   ./scripts/act-with-cache.sh --list             # List available jobs
#
# Prerequisites:
#   Build local images first: ./.act/build-images.sh 3.4
#
# Cache is stored in: ~/.cache/actcache (or ACT_CACHE_PATH if set)

set -euo pipefail

CACHE_PATH="${ACT_CACHE_PATH:-$HOME/.cache/actcache}"
CACHE_PORT="${ACT_CACHE_PORT:-0}"  # 0 = random available port
RUBY_VERSION="${ACT_RUBY_VERSION:-3.4}"

# Ensure cache directory exists
mkdir -p "$CACHE_PATH"

echo "==> Act with Cache Support"
echo "    Cache path: $CACHE_PATH"
echo "    Ruby image: act-ruby-$RUBY_VERSION (local)"
echo ""

# Check if local image exists and tag it with remote name
REMOTE_IMAGE="ghcr.io/datadog/images-rb/engines/ruby:${RUBY_VERSION}-gnu-gcc"
LOCAL_IMAGE="act-ruby-$RUBY_VERSION"

if docker image inspect "$LOCAL_IMAGE" &>/dev/null; then
    # Tag local image as the remote image name so act uses it
    docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE" 2>/dev/null || true
    PULL_ARG="--pull=false"
    echo "    Using local image: $LOCAL_IMAGE"
else
    echo "WARNING: Local image $LOCAL_IMAGE not found."
    echo "         Build it with: ./.act/build-images.sh $RUBY_VERSION"
    echo "         Falling back to remote image (slower - will install Node.js)."
    PULL_ARG=""
fi
echo ""

# Run act with cache server enabled
# Note: host.docker.internal is required for Docker Desktop on macOS
exec act \
    --cache-server-path "$CACHE_PATH" \
    --cache-server-port "$CACHE_PORT" \
    --cache-server-addr "host.docker.internal" \
    $PULL_ARG \
    "$@"
