#!/usr/bin/env bash
# Build act-compatible Docker images with Node.js pre-installed
# This avoids the slow apt-get install on every act run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUBY_VERSIONS="${@:-3.4}"

for version in $RUBY_VERSIONS; do
    echo "==> Building act-ruby-$version..."

    # Generate Dockerfile for this version
    cat > "Dockerfile.ruby-$version" << EOF
# Local act-compatible image with Ruby + Node.js pre-installed
FROM ghcr.io/datadog/images-rb/engines/ruby:$version-gnu-gcc

RUN apt-get update && \\
    apt-get install -y --no-install-recommends nodejs npm && \\
    apt-get clean && \\
    rm -rf /var/lib/apt/lists/*

RUN ruby --version && node --version
EOF

    # Build for AMD64 platform (matching CI) - this uses emulation on Apple Silicon
    docker build --platform linux/amd64 -t "act-ruby-$version" -f "Dockerfile.ruby-$version" .
    echo "==> Built act-ruby-$version"
done

echo ""
echo "Done! Use with:"
echo "  act -P ghcr.io/datadog/images-rb/engines/ruby:3.4-gnu-gcc=act-ruby-3.4"
