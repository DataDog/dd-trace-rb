#!/bin/bash
set -e

# =============================================================================
# Build script for dd-trace-rb with macOS native support
# =============================================================================
#
# This script builds the libdatadog gem with macOS (arm64-darwin / x86_64-darwin)
# support and compiles the native extension for dd-trace-rb.
#
# Prerequisites:
# - Ruby with bundler installed
# - gh CLI tool (for downloading GitHub releases)
# - Xcode Command Line Tools (for compiling native extensions)
#
# Usage:
#   ./scripts/build_macos_native.sh
#
# The script performs the following steps:
# 1. Clones/updates the libdatadog repository
# 2. Applies macOS platform patches to libdatadog
# 3. Downloads pre-built darwin binaries from GitHub releases
# 4. Packages the libdatadog gem with macOS support
# 5. Installs the gem locally
# 6. Compiles the dd-trace-rb native extension
# 7. Fixes dylib paths for runtime loading
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DD_TRACE_RB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
LIBDATADOG_VERSION="25.0.0"
LIBDATADOG_REPO="https://github.com/DataDog/libdatadog.git"
LIBDATADOG_DIR="${LIBDATADOG_DIR:-/tmp/libdatadog-build}"
RUBY_VERSION=$(ruby -e 'puts RUBY_VERSION')
RUBY_PLATFORM=$(ruby -e 'puts Gem::Platform.local.to_s')

echo "==================================================================="
echo "Building dd-trace-rb with macOS native support"
echo "==================================================================="
echo ""
echo "Configuration:"
echo "  dd-trace-rb directory: $DD_TRACE_RB_DIR"
echo "  libdatadog directory:  $LIBDATADOG_DIR"
echo "  libdatadog version:    $LIBDATADOG_VERSION"
echo "  Ruby version:          $RUBY_VERSION"
echo "  Ruby platform:         $RUBY_PLATFORM"
echo ""

# Determine macOS platform
case "$RUBY_PLATFORM" in
  *arm64-darwin*|*aarch64-darwin*)
    MACOS_PLATFORM="arm64-darwin"
    ;;
  *x86_64-darwin*)
    MACOS_PLATFORM="x86_64-darwin"
    ;;
  *)
    echo "ERROR: Unsupported platform: $RUBY_PLATFORM"
    echo "This script only supports arm64-darwin and x86_64-darwin"
    exit 1
    ;;
esac
echo "Detected macOS platform: $MACOS_PLATFORM"
echo ""

# =============================================================================
# Step 1: Clone or update libdatadog
# =============================================================================
echo "==================================================================="
echo "Step 1: Setting up libdatadog repository"
echo "==================================================================="

if [ -d "$LIBDATADOG_DIR" ]; then
  echo "libdatadog directory exists, updating..."
  cd "$LIBDATADOG_DIR"
  git fetch origin
  git reset --hard origin/main
else
  echo "Cloning libdatadog..."
  git clone "$LIBDATADOG_REPO" "$LIBDATADOG_DIR"
  cd "$LIBDATADOG_DIR"
fi
echo ""

# =============================================================================
# Step 2: Apply macOS platform patches
# =============================================================================
echo "==================================================================="
echo "Step 2: Applying macOS platform patches"
echo "==================================================================="

cd "$LIBDATADOG_DIR/ruby"

# Patch Rakefile to include macOS platforms
cat > /tmp/rakefile_patch.rb << 'PATCHEOF'
# Add macOS platforms to LIB_GITHUB_RELEASES
rakefile_content = File.read("Rakefile")

# Check if darwin platforms are already added
unless rakefile_content.include?("arm64-darwin")
  # Find the position after the last linux entry in LIB_GITHUB_RELEASES
  insert_marker = '    ruby_platform: "x86_64-linux"
  }'

  darwin_entries = ',
  {
    file: "libdatadog-aarch64-apple-darwin.tar.gz",
    sha256: "2292639fa885a5f126e7bdf0bbdfd9b08ef54835bfa5c1c6291db15d4ed1b807",
    ruby_platform: "arm64-darwin"
  },
  {
    file: "libdatadog-x86_64-apple-darwin.tar.gz",
    sha256: "e8fa9cd5ad8ec81defa2b7eeb62fea8eaca3df37c945be36434e9a080e14c7c5",
    ruby_platform: "x86_64-darwin"
  }'

  rakefile_content = rakefile_content.sub(insert_marker, insert_marker + darwin_entries)

  # Add macOS packaging lines
  package_insert = 'Helpers.package_for(gemspec, ruby_platform: "aarch64-linux", files: Helpers.files_for("aarch64-linux", "aarch64-linux-musl"))'
  darwin_packaging = '

  # macOS packages
  Helpers.package_for(gemspec, ruby_platform: "arm64-darwin", files: Helpers.files_for("arm64-darwin"))
  Helpers.package_for(gemspec, ruby_platform: "x86_64-darwin", files: Helpers.files_for("x86_64-darwin"))'

  rakefile_content = rakefile_content.sub(package_insert, package_insert + darwin_packaging)

  File.write("Rakefile", rakefile_content)
  puts "Patched Rakefile with macOS platforms"
else
  puts "Rakefile already has macOS platforms"
end
PATCHEOF
ruby /tmp/rakefile_patch.rb

# Patch lib/libdatadog.rb to normalize Darwin platform strings
cat > /tmp/libdatadog_patch.rb << 'PATCHEOF'
libdatadog_content = File.read("lib/libdatadog.rb")

# Check if darwin normalization is already added
unless libdatadog_content.include?("darwin-?\\d*")
  # Find the position after the -gnu normalization
  insert_marker = '      platform = platform[0..-5]
    end'

  darwin_normalization = '

    # Normalize macOS/Darwin platform strings by stripping the version number.
    # e.g., "arm64-darwin-24" -> "arm64-darwin", "x86_64-darwin-19" -> "x86_64-darwin"
    if platform.include?("darwin")
      platform = platform.gsub(/-darwin-?\d*$/, "-darwin")
    end'

  libdatadog_content = libdatadog_content.sub(insert_marker, insert_marker + darwin_normalization)

  File.write("lib/libdatadog.rb", libdatadog_content)
  puts "Patched lib/libdatadog.rb with Darwin platform normalization"
else
  puts "lib/libdatadog.rb already has Darwin normalization"
end
PATCHEOF
ruby /tmp/libdatadog_patch.rb
echo ""

# =============================================================================
# Step 3: Download pre-built darwin binaries
# =============================================================================
echo "==================================================================="
echo "Step 3: Downloading pre-built darwin binaries from GitHub"
echo "==================================================================="

VENDOR_DIR="vendor/libdatadog-${LIBDATADOG_VERSION}"
TMP_DOWNLOAD_DIR="/tmp/libdatadog-download-$$"

mkdir -p "$TMP_DOWNLOAD_DIR"
mkdir -p "$VENDOR_DIR"/{aarch64-linux,aarch64-linux-musl,x86_64-linux,x86_64-linux-musl,arm64-darwin,x86_64-darwin}

echo "Downloading release tarballs using gh CLI..."
gh release download "v${LIBDATADOG_VERSION}" \
  --repo DataDog/libdatadog \
  --pattern "libdatadog-*.tar.gz" \
  --dir "$TMP_DOWNLOAD_DIR" \
  --skip-existing

echo ""
echo "Copying tarballs to vendor directory..."

# Map tarball names to Ruby platform directories
cp "$TMP_DOWNLOAD_DIR/libdatadog-aarch64-alpine-linux-musl.tar.gz" "$VENDOR_DIR/aarch64-linux-musl/" 2>/dev/null || true
cp "$TMP_DOWNLOAD_DIR/libdatadog-aarch64-unknown-linux-gnu.tar.gz" "$VENDOR_DIR/aarch64-linux/" 2>/dev/null || true
cp "$TMP_DOWNLOAD_DIR/libdatadog-x86_64-alpine-linux-musl.tar.gz" "$VENDOR_DIR/x86_64-linux-musl/" 2>/dev/null || true
cp "$TMP_DOWNLOAD_DIR/libdatadog-x86_64-unknown-linux-gnu.tar.gz" "$VENDOR_DIR/x86_64-linux/" 2>/dev/null || true
cp "$TMP_DOWNLOAD_DIR/libdatadog-aarch64-apple-darwin.tar.gz" "$VENDOR_DIR/arm64-darwin/"
cp "$TMP_DOWNLOAD_DIR/libdatadog-x86_64-apple-darwin.tar.gz" "$VENDOR_DIR/x86_64-darwin/"

rm -rf "$TMP_DOWNLOAD_DIR"
echo ""

# =============================================================================
# Step 4: Build and package the libdatadog gem
# =============================================================================
echo "==================================================================="
echo "Step 4: Building libdatadog gem with macOS support"
echo "==================================================================="

bundle install
bundle exec rake extract
bundle exec rake package

echo ""
echo "Built gems:"
ls -la pkg/*.gem
echo ""

# Find the correct gem for this platform
LIBDATADOG_GEM=$(ls pkg/libdatadog-*-${MACOS_PLATFORM}.gem 2>/dev/null | head -1)
if [ -z "$LIBDATADOG_GEM" ]; then
  echo "ERROR: Could not find gem for platform $MACOS_PLATFORM"
  exit 1
fi
echo "Will install: $LIBDATADOG_GEM"
echo ""

# =============================================================================
# Step 5: Install the libdatadog gem locally
# =============================================================================
echo "==================================================================="
echo "Step 5: Installing libdatadog gem locally"
echo "==================================================================="

# Install the gem to the dd-trace-rb bundle
cd "$DD_TRACE_RB_DIR"
gem install "$LIBDATADOG_DIR/ruby/$LIBDATADOG_GEM" --no-document

echo ""
echo "Verifying installation..."
ruby -e "require 'libdatadog'; puts \"Libdatadog version: #{Libdatadog::VERSION}\"; puts \"Available binaries: #{Libdatadog.available_binaries}\"; puts \"pkgconfig folder: #{Libdatadog.pkgconfig_folder}\""
echo ""

# =============================================================================
# Step 6: Compile the dd-trace-rb native extension
# =============================================================================
echo "==================================================================="
echo "Step 6: Compiling dd-trace-rb native extension"
echo "==================================================================="

cd "$DD_TRACE_RB_DIR"
bundle install

# Force rebuild of the native extension
cd ext/libdatadog_api
ruby extconf.rb
make clean 2>/dev/null || true
make

# Find the compiled bundle
NATIVE_BUNDLE=$(ls *.bundle 2>/dev/null | head -1)
if [ -z "$NATIVE_BUNDLE" ]; then
  echo "ERROR: Native extension compilation failed"
  exit 1
fi
echo ""
echo "Compiled native extension: $NATIVE_BUNDLE"
echo ""

# =============================================================================
# Step 7: Fix dylib paths for runtime loading
# =============================================================================
echo "==================================================================="
echo "Step 7: Fixing dylib paths for runtime loading"
echo "==================================================================="

# Get the libdatadog library path
LIBDATADOG_LIB_PATH=$(ruby -e "require 'libdatadog'; puts Libdatadog.ld_library_path")
echo "Libdatadog library path: $LIBDATADOG_LIB_PATH"

# Check current dylib references
echo ""
echo "Current dylib references:"
otool -L "$NATIVE_BUNDLE" | grep -E "(libdatadog|datadog)" || true

# Find any references that need fixing
BAD_DYLIB_REF=$(otool -L "$NATIVE_BUNDLE" | grep libdatadog_profiling_ffi.dylib | awk '{print $1}' | head -1)

if [ -n "$BAD_DYLIB_REF" ] && [ "$BAD_DYLIB_REF" != "@rpath/libdatadog_profiling_ffi.dylib" ]; then
  echo ""
  echo "Fixing dylib reference: $BAD_DYLIB_REF"

  # Update the install name to use @rpath
  install_name_tool -change "$BAD_DYLIB_REF" "@rpath/libdatadog_profiling_ffi.dylib" "$NATIVE_BUNDLE"

  # Add rpath if not present
  if ! otool -l "$NATIVE_BUNDLE" | grep -q "$LIBDATADOG_LIB_PATH"; then
    install_name_tool -add_rpath "$LIBDATADOG_LIB_PATH" "$NATIVE_BUNDLE"
  fi

  echo ""
  echo "Fixed dylib references:"
  otool -L "$NATIVE_BUNDLE" | grep -E "(libdatadog|datadog)" || true
else
  echo "Dylib references are already correct"
fi

# Copy the bundle to the lib directory for easy loading
RUBY_ABI_VERSION=$(ruby -e 'puts RbConfig::CONFIG["ruby_version"]')
NATIVE_PLATFORM=$(ruby -e 'puts RUBY_PLATFORM')
TARGET_BUNDLE="$DD_TRACE_RB_DIR/lib/libdatadog_api.${RUBY_ABI_VERSION}_${NATIVE_PLATFORM}.bundle"

echo ""
echo "Copying bundle to: $TARGET_BUNDLE"
cp "$NATIVE_BUNDLE" "$TARGET_BUNDLE"
echo ""

# =============================================================================
# Verification
# =============================================================================
echo "==================================================================="
echo "Verification"
echo "==================================================================="

cd "$DD_TRACE_RB_DIR"
echo "Testing native extension loading..."
ruby -I lib -e "
require 'libdatadog'
require 'libdatadog_api'

puts 'SUCCESS: Native extension loaded!'
puts ''
puts 'Libdatadog info:'
puts \"  Version: #{Libdatadog::VERSION}\"
puts \"  Platform: #{Libdatadog.current_platform}\"
puts \"  Available binaries: #{Libdatadog.available_binaries}\"
puts \"  pkgconfig folder: #{Libdatadog.pkgconfig_folder}\"
puts \"  LD library path: #{Libdatadog.ld_library_path}\"
"

echo ""
echo "==================================================================="
echo "Build complete!"
echo "==================================================================="
echo ""
echo "The native extension has been compiled and installed."
echo "You can now use dd-trace-rb with full native support on macOS."
echo ""
echo "To use in your application, add this to your Gemfile:"
echo ""
echo "  gem 'datadog', path: '$DD_TRACE_RB_DIR'"
echo ""
