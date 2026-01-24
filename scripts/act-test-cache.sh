#!/usr/bin/env bash
# Test script to verify bundle caching works like the real CI
# Run this twice - second run should show cache hit in both batch and build-test jobs
#
# Usage: ./scripts/act-test-cache.sh [ruby-version]
# Example: ./scripts/act-test-cache.sh 3.3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

RUBY_VERSION="${1:-3.4}"
CACHE_PATH="${ACT_CACHE_PATH:-$HOME/.cache/actcache}"

echo "==> Testing Bundle Cache (mirrors _unit_test.yml)"
echo "    Ruby version: $RUBY_VERSION"
echo "    Cache path: $CACHE_PATH"
echo ""

EXTRA_ARGS=""
if [ "$RUBY_VERSION" != "3.4" ]; then
    EXTRA_ARGS="--input ruby-version=$RUBY_VERSION"
fi

echo "==> Running _test-bundle-cache.yml workflow..."
echo ""

act workflow_dispatch \
    --cache-server-path "$CACHE_PATH" \
    --cache-server-addr "host.docker.internal" \
    --container-architecture linux/amd64 \
    -W .github/workflows/_test-bundle-cache.yml \
    $EXTRA_ARGS

echo ""
echo "==> Cache directory contents:"
ls -la "$CACHE_PATH" 2>/dev/null || echo "    (empty or not created)"

echo ""
echo "==> Run this script again to verify cache hits"
