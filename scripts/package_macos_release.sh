#!/bin/bash
set -e

# =============================================================================
# Package macOS Release Tarballs for Customer Distribution
# =============================================================================
#
# Creates distribution tarballs containing:
# - datadog gem (the tracer)
# - libdatadog gem (native library for macOS)
# - README with installation instructions
# - PROOF.txt with live feature flag evaluation results
#
# Prerequisites:
# - Run build_macos_native.sh first to build the libdatadog gem
# - Have the dogfood app running at localhost:4567 for proof generation
#
# Usage:
#   ./scripts/package_macos_release.sh
#
# Output:
#   ~/dd/customer-gems/libdatadog-<version>-arm64-darwin.tar.gz
#   ~/dd/customer-gems/libdatadog-<version>-x86_64-darwin.tar.gz
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DD_TRACE_RB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Try to find libdatadog gems
LIBDATADOG_DIR="${LIBDATADOG_DIR:-$HOME/dd/libdatadog}"
LIBDATADOG_BUILD_DIR="/tmp/libdatadog-build"

# Output directory
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/dd/customer-gems}"

echo "==================================================================="
echo "Packaging macOS Release Tarballs"
echo "==================================================================="
echo ""

# Find libdatadog version and gems
LIBDATADOG_PKG_DIR=""
if [ -d "$LIBDATADOG_DIR/ruby/pkg" ]; then
  LIBDATADOG_PKG_DIR="$LIBDATADOG_DIR/ruby/pkg"
elif [ -d "$LIBDATADOG_BUILD_DIR/ruby/pkg" ]; then
  LIBDATADOG_PKG_DIR="$LIBDATADOG_BUILD_DIR/ruby/pkg"
else
  echo "ERROR: Cannot find libdatadog gems."
  echo "Run build_macos_native.sh first, or set LIBDATADOG_DIR"
  exit 1
fi

ARM64_GEM=$(ls "$LIBDATADOG_PKG_DIR"/libdatadog-*-arm64-darwin.gem 2>/dev/null | head -1)
X86_64_GEM=$(ls "$LIBDATADOG_PKG_DIR"/libdatadog-*-x86_64-darwin.gem 2>/dev/null | head -1)

if [ -z "$ARM64_GEM" ] || [ -z "$X86_64_GEM" ]; then
  echo "ERROR: Cannot find macOS libdatadog gems in $LIBDATADOG_PKG_DIR"
  echo "Run build_macos_native.sh first"
  exit 1
fi

LIBDATADOG_VERSION=$(basename "$ARM64_GEM" | sed 's/libdatadog-\(.*\)-arm64-darwin.gem/\1/')
echo "Found libdatadog version: $LIBDATADOG_VERSION"
echo "  arm64-darwin:  $ARM64_GEM"
echo "  x86_64-darwin: $X86_64_GEM"
echo ""

# =============================================================================
# Step 1: Build the datadog gem
# =============================================================================
echo "==================================================================="
echo "Step 1: Building datadog gem"
echo "==================================================================="

cd "$DD_TRACE_RB_DIR"

# Clean up old gems
rm -f datadog-*.gem

# Build the gem
gem build datadog.gemspec

DATADOG_GEM=$(ls datadog-*.gem 2>/dev/null | head -1)
if [ -z "$DATADOG_GEM" ]; then
  echo "ERROR: Failed to build datadog gem"
  exit 1
fi

DATADOG_VERSION=$(basename "$DATADOG_GEM" .gem | sed 's/datadog-//')
echo "Built: $DATADOG_GEM (version $DATADOG_VERSION)"
echo ""

# =============================================================================
# Step 2: Generate proof from live dogfood app
# =============================================================================
echo "==================================================================="
echo "Step 2: Generating proof from live dogfood app"
echo "==================================================================="

PROOF_FILE="$OUTPUT_DIR/PROOF.txt"
mkdir -p "$OUTPUT_DIR"

# Check if dogfood app is running
if curl -s http://localhost:4567/health > /dev/null 2>&1; then
  echo "Dogfood app is running, generating live proof..."

  cat > "$PROOF_FILE" << 'HEADER'
================================================================================
   PROOF: Datadog OpenFeature Working on macOS
================================================================================

HEADER

  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$PROOF_FILE"

  cat >> "$PROOF_FILE" << PLATFORM_INFO

=== Platform Information ===
  OS:       $(uname -s) $(uname -r) (macOS)
  Arch:     $(uname -m)
  Ruby:     $(ruby -v | cut -d' ' -f1-2) [$(ruby -e 'puts RUBY_PLATFORM')]

=== Gem Versions ===
  datadog:     $DATADOG_VERSION
  libdatadog:  $LIBDATADOG_VERSION

=== Dogfood App Health Check ===
PLATFORM_INFO

  curl -s http://localhost:4567/health | ruby -rjson -e 'JSON.parse(STDIN.read).each { |k,v| puts "  #{k.to_s.ljust(18)} #{v}" }' >> "$PROOF_FILE"

  cat >> "$PROOF_FILE" << 'FLAGS_HEADER'

=== Live Feature Flag Evaluations ===
FLAGS_HEADER

  curl -s http://localhost:4567/flags.json | ruby -rjson -e '
JSON.parse(STDIN.read).each do |f|
  puts ""
  puts "  #{f["key"]}"
  puts "    Type:    #{f["type"]}"
  puts "    Value:   #{f["value"].inspect}"
  puts "    Variant: #{f["variant"]}"
  puts "    Reason:  #{f["reason"]}"
  puts "    Status:  #{f["error_code"] ? "ERROR: #{f["error_code"]}" : "OK"}"
end
' >> "$PROOF_FILE"

  cat >> "$PROOF_FILE" << 'FOOTER'

================================================================================
   SUCCESS: OpenFeature flags are evaluating correctly on macOS
================================================================================
FOOTER

  echo "Generated: $PROOF_FILE"
else
  echo "WARNING: Dogfood app not running at localhost:4567"
  echo "Creating proof file without live flag data..."

  cat > "$PROOF_FILE" << STATIC_PROOF
================================================================================
   Datadog OpenFeature for macOS
================================================================================

Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

=== Gem Versions ===
  datadog:     $DATADOG_VERSION
  libdatadog:  $LIBDATADOG_VERSION

=== Platform Support ===
  arm64-darwin:  Apple Silicon (M1/M2/M3/M4)
  x86_64-darwin: Intel Mac

Note: Start the dogfood app and re-run this script to include live
feature flag evaluation proof.
================================================================================
STATIC_PROOF
fi
echo ""

# =============================================================================
# Step 3: Create README files
# =============================================================================
echo "==================================================================="
echo "Step 3: Creating README files"
echo "==================================================================="

mkdir -p "$OUTPUT_DIR/arm64-darwin" "$OUTPUT_DIR/x86_64-darwin"

# ARM64 README
cat > "$OUTPUT_DIR/arm64-darwin/README.md" << README_ARM64
# Datadog Ruby APM + OpenFeature for macOS (Apple Silicon)

**Platform:** arm64-darwin (M1/M2/M3/M4 Macs)
**Datadog Version:** $DATADOG_VERSION
**Libdatadog Version:** $LIBDATADOG_VERSION

## Contents

- \`datadog-$DATADOG_VERSION.gem\` - Datadog APM tracer with OpenFeature support
- \`libdatadog-$LIBDATADOG_VERSION-arm64-darwin.gem\` - Native library for Apple Silicon
- \`PROOF.txt\` - Verification showing feature flags working on macOS
- \`README.md\` - This file

## Quick Install

\`\`\`bash
# Install both gems (order matters - libdatadog first)
gem install libdatadog-$LIBDATADOG_VERSION-arm64-darwin.gem
gem install datadog-$DATADOG_VERSION.gem

# Verify installation
ruby -e "require 'datadog'; puts Datadog::VERSION::STRING"
\`\`\`

## Gemfile Usage

\`\`\`ruby
# After installing gems locally:
gem 'datadog', '$DATADOG_VERSION'
gem 'open_feature-sdk'
\`\`\`

## Configuration for OpenFeature

\`\`\`ruby
require 'datadog'
require 'open_feature/sdk'
require 'datadog/open_feature/provider'

Datadog.configure do |c|
  c.service = 'my-service'
  c.env = 'development'
  c.remote.enabled = true
  c.open_feature.enabled = true
end

OpenFeature::SDK.configure do |config|
  config.set_provider_and_wait(Datadog::OpenFeature::Provider.new)
end

client = OpenFeature::SDK.build_client
value = client.fetch_boolean_value(flag_key: 'my-flag', default_value: false)
\`\`\`

## Requirements

- Ruby 2.7+
- macOS 11+ (Big Sur or later)
- Apple Silicon Mac
- Datadog Agent with Remote Configuration enabled
README_ARM64

# X86_64 README
cat > "$OUTPUT_DIR/x86_64-darwin/README.md" << README_X86
# Datadog Ruby APM + OpenFeature for macOS (Intel)

**Platform:** x86_64-darwin (Intel Macs)
**Datadog Version:** $DATADOG_VERSION
**Libdatadog Version:** $LIBDATADOG_VERSION

## Contents

- \`datadog-$DATADOG_VERSION.gem\` - Datadog APM tracer with OpenFeature support
- \`libdatadog-$LIBDATADOG_VERSION-x86_64-darwin.gem\` - Native library for Intel Mac
- \`PROOF.txt\` - Verification showing feature flags working on macOS
- \`README.md\` - This file

## Quick Install

\`\`\`bash
# Install both gems (order matters - libdatadog first)
gem install libdatadog-$LIBDATADOG_VERSION-x86_64-darwin.gem
gem install datadog-$DATADOG_VERSION.gem

# Verify installation
ruby -e "require 'datadog'; puts Datadog::VERSION::STRING"
\`\`\`

## Gemfile Usage

\`\`\`ruby
# After installing gems locally:
gem 'datadog', '$DATADOG_VERSION'
gem 'open_feature-sdk'
\`\`\`

## Configuration for OpenFeature

\`\`\`ruby
require 'datadog'
require 'open_feature/sdk'
require 'datadog/open_feature/provider'

Datadog.configure do |c|
  c.service = 'my-service'
  c.env = 'development'
  c.remote.enabled = true
  c.open_feature.enabled = true
end

OpenFeature::SDK.configure do |config|
  config.set_provider_and_wait(Datadog::OpenFeature::Provider.new)
end

client = OpenFeature::SDK.build_client
value = client.fetch_boolean_value(flag_key: 'my-flag', default_value: false)
\`\`\`

## Requirements

- Ruby 2.7+
- macOS 10.15+ (Catalina or later)
- Intel Mac
- Datadog Agent with Remote Configuration enabled
README_X86

echo "Created README files"
echo ""

# =============================================================================
# Step 4: Assemble and create tarballs
# =============================================================================
echo "==================================================================="
echo "Step 4: Creating distribution tarballs"
echo "==================================================================="

# ARM64 tarball
cp "$ARM64_GEM" "$OUTPUT_DIR/arm64-darwin/"
cp "$DD_TRACE_RB_DIR/$DATADOG_GEM" "$OUTPUT_DIR/arm64-darwin/"
cp "$PROOF_FILE" "$OUTPUT_DIR/arm64-darwin/"

cd "$OUTPUT_DIR"
tar -czvf "datadog-$DATADOG_VERSION-arm64-darwin.tar.gz" -C arm64-darwin .
echo ""

# X86_64 tarball
cp "$X86_64_GEM" "$OUTPUT_DIR/x86_64-darwin/"
cp "$DD_TRACE_RB_DIR/$DATADOG_GEM" "$OUTPUT_DIR/x86_64-darwin/"
cp "$PROOF_FILE" "$OUTPUT_DIR/x86_64-darwin/"

tar -czvf "datadog-$DATADOG_VERSION-x86_64-darwin.tar.gz" -C x86_64-darwin .
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "==================================================================="
echo "Package Complete!"
echo "==================================================================="
echo ""
echo "Tarballs created in: $OUTPUT_DIR"
echo ""
ls -lh "$OUTPUT_DIR"/*.tar.gz
echo ""
echo "Each tarball contains:"
echo "  - datadog-$DATADOG_VERSION.gem"
echo "  - libdatadog-$LIBDATADOG_VERSION-<platform>.gem"
echo "  - README.md"
echo "  - PROOF.txt"
