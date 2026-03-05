#!/usr/bin/env bash
# frozen_string_literal: false
#
# compile_and_test.sh — Build dd-trace-rb C extensions against a local
# libdatadog gem tree and run the native specs.
#
# Prerequisites:
#   1. A populated libdatadog vendor tree.  Build it with:
#        cd <libdatadog>/ruby && rake compile
#
#   2. A Gemfile entry pointing at that tree:
#        gem 'libdatadog', path: '<path-to-libdatadog>/ruby'
#      then run:  bundle install
#
#   3. pkg-config must be available in $PATH.
#
# Usage:
#   ./compile_and_test.sh                    # compile + run specs
#   ./compile_and_test.sh --compile-only     # compile only, skip specs
#   ./compile_and_test.sh --test-only        # skip compile, run specs only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --------------------------------------------------------------------------
# Platform detection
# --------------------------------------------------------------------------

OS="$(uname -s)"
case "$OS" in
  Darwin*) IS_MACOS=true  ;;
  *)       IS_MACOS=false ;;
esac

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

# Spec file(s) to run after a successful compile.  Add more as needed.
SPEC_FILES=(
  spec/datadog/tracing/transport/libdatadog_native/tracer_span_spec.rb
)

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

# Return the expected libdatadog_api shared object path under lib/ for this platform.
# On macOS this is a .bundle, on Linux a .so.
# Note: we must query Ruby for RUBY_VERSION because bash's own $RUBY_VERSION
# is the bash version string, not the Ruby version.
expected_api_lib() {
  local short_ver
  short_ver=$(ruby -e 'print RUBY_VERSION[/\d+\.\d+/]')
  local platform
  platform=$(ruby -e "print RUBY_PLATFORM")
  local ext
  if $IS_MACOS; then ext="bundle"; else ext="so"; fi
  echo "lib/libdatadog_api.${short_ver}_${platform}.${ext}"
}

check_prereqs() {
  if ! command -v pkg-config >/dev/null 2>&1; then
    err "pkg-config is not installed.  Install it (e.g. brew install pkg-config, nix-env -iA nixpkgs.pkg-config)."
    exit 1
  fi

  if ! bundle exec ruby -e "require 'libdatadog'; exit(Libdatadog.pkgconfig_folder ? 0 : 1)" 2>/dev/null; then
    err "Libdatadog.pkgconfig_folder returned nil."
    err "Make sure:"
    err "  1. You ran 'rake compile' inside the libdatadog/ruby directory."
    err "  2. Your Gemfile has:  gem 'libdatadog', path: '<path-to-libdatadog>/ruby'"
    err "  3. You ran 'bundle install' after editing the Gemfile."
    exit 1
  fi
}

# --------------------------------------------------------------------------
# Nix pkg-config workaround
#
# The Nix pkg-config wrapper ignores PKG_CONFIG_PATH and instead reads
# from a platform-qualified variant (e.g. PKG_CONFIG_PATH_x86_64_unknown_linux_gnu).
# Ruby's mkmf only sets PKG_CONFIG_PATH, so extconf.rb's pkg_config()
# call silently fails under Nix.
#
# Detect this situation and propagate PKG_CONFIG_PATH into the variant
# that the Nix wrapper actually consults.
# --------------------------------------------------------------------------

setup_nix_pkg_config() {
  # Only needed on Linux (Nix on macOS uses a different approach)
  if $IS_MACOS; then
    return
  fi

  local pkgconfig_folder
  pkgconfig_folder=$(bundle exec ruby -e "require 'libdatadog'; puts Libdatadog.pkgconfig_folder" 2>/dev/null) || return 0

  # Check if the Nix wrapper is in play by looking at the pkg-config path
  local pkg_config_path
  pkg_config_path=$(command -v pkg-config 2>/dev/null) || return 0

  if [[ "$pkg_config_path" != /nix/store/* ]]; then
    return  # Not using Nix pkg-config, nothing to do
  fi

  # Find the platform-qualified env var name the Nix wrapper uses.
  # It looks like PKG_CONFIG_PATH_<triple> where triple has - replaced with _.
  # We extract it from the wrapper script itself.
  local nix_var
  nix_var=$(grep -oP 'PKG_CONFIG_PATH_\w+' "$pkg_config_path" 2>/dev/null | head -1) || true

  if [ -z "$nix_var" ]; then
    warn "Could not determine Nix pkg-config wrapper variable name."
    warn "If compilation fails with 'pkg-config for datadog_profiling_with_rpath... not found',"
    warn "you may need to manually export the correct PKG_CONFIG_PATH variant."
    return
  fi

  # Append libdatadog's pkgconfig folder to the Nix-specific variable
  local current_val="${!nix_var:-}"
  if [ -n "$current_val" ]; then
    export "${nix_var}=${current_val}:${pkgconfig_folder}"
  else
    export "${nix_var}=${pkgconfig_folder}"
  fi

  log "Nix pkg-config detected: exported ${nix_var} with libdatadog pkgconfig path"

  # Verify it actually works now
  if ! pkg-config --exists datadog_profiling_with_rpath 2>/dev/null; then
    warn "pkg-config still cannot find datadog_profiling_with_rpath after Nix workaround."
    warn "You may need to debug the Nix pkg-config wrapper manually."
  fi
}

# --------------------------------------------------------------------------
# Version constraint check
#
# dd-trace-rb's extconf.rb calls `gem 'libdatadog', <constraint>` outside
# of bundler.  When developing against a local libdatadog whose version
# differs from the pinned constraint, extconf will refuse to load it.
#
# This function detects the mismatch and tells you exactly what to change.
# The fix is a one-line edit that should NOT be committed.
# --------------------------------------------------------------------------

check_version_constraint() {
  local helpers_file="ext/libdatadog_extconf_helpers.rb"

  # Extract the constraint string, e.g. "~> 25.0.0.1.0"
  local constraint
  constraint=$(ruby -e "
    load '${helpers_file}'
    puts Datadog::LibdatadogExtconfHelpers::LIBDATADOG_VERSION
  " 2>/dev/null) || return 0  # if the file can't be loaded, skip check

  # Extract the installed libdatadog gem version
  local installed_version
  installed_version=$(bundle exec ruby -e "
    require 'libdatadog'
    puts Libdatadog::VERSION
  " 2>/dev/null) || return 0

  # Check whether the constraint matches the installed version
  local matches
  matches=$(ruby -e "
    require 'rubygems'
    req = Gem::Requirement.new('${constraint}')
    ver = Gem::Version.new('${installed_version}')
    puts req.satisfied_by?(ver) ? 'yes' : 'no'
  " 2>/dev/null) || return 0

  if [ "$matches" = "no" ]; then
    # Figure out what the constraint should be
    local major_version
    major_version=$(echo "$installed_version" | cut -d. -f1)

    err "Version mismatch!"
    err ""
    err "  ${helpers_file} has:  LIBDATADOG_VERSION = '${constraint}'"
    err "  Local gem version:    ${installed_version}"
    err ""
    err "The constraint does not match.  For local development, change the"
    err "constraint in ${helpers_file} to:"
    err ""
    err "  LIBDATADOG_VERSION = '~> ${major_version}.0.0.1.0'"
    err ""
    err "Do NOT commit this change."
    exit 1
  fi

  log "Version constraint OK (${constraint} matches ${installed_version})"
}

# --------------------------------------------------------------------------
# Compile
# --------------------------------------------------------------------------

do_compile() {
  check_prereqs
  check_version_constraint
  setup_nix_pkg_config

  # Clean stale build artefacts for the libdatadog_api extension.
  # Without this, a previously-generated dummy Makefile (from when
  # libdatadog was unavailable) will be reused and produce nothing.
  local platform_dir
  platform_dir=$(ruby -e "puts Gem::Platform.local.to_s")
  local build_dir="tmp/${platform_dir}"

  if [ -d "$build_dir" ]; then
    log "Cleaning stale libdatadog_api build artefacts in ${build_dir}..."
    rm -rf "${build_dir}"/libdatadog_api*
  fi

  # Determine the expected output path for the libdatadog_api shared object.
  local api_lib
  api_lib=$(expected_api_lib)
  log "Expected libdatadog_api artifact: ${api_lib}"

  # Remove it so we can unambiguously tell whether the build produced it.
  rm -f "$api_lib"

  log "Compiling C extensions (platform: ${OS})..."

  # The profiling native extension may fail during local development:
  #   - On macOS: profiling is not supported at all.
  #   - On Linux: the profiling C code in dd-trace-rb may be out of date
  #     with a newer local libdatadog (API signature mismatches).
  #
  # We tolerate profiling failures — this script's purpose is building and
  # testing the libdatadog_api extension.  We detect success by checking
  # whether the expected shared object was produced.
  if bundle exec rake compile 2>&1; then
    log "All extensions compiled successfully."
  else
    if [ -f "$api_lib" ]; then
      warn "rake compile exited non-zero, but libdatadog_api was built: ${api_lib}"
      warn "The failure is likely the profiling native extension."
      if $IS_MACOS; then
        warn "This is expected on macOS (profiling is not supported)."
      else
        warn "This is expected during local development when dd-trace-rb's"
        warn "profiling C code is out of date with the local libdatadog."
      fi
    else
      err "rake compile failed and no libdatadog_api bundle was produced."
      err "Review the output above for details."

      # Provide a hint for the common Nix pkg-config issue
      if [[ "$(command -v pkg-config 2>/dev/null)" == /nix/store/* ]]; then
        err ""
        err "Hint: You are using a Nix pkg-config wrapper. If you see"
        err "'pkg-config for datadog_profiling_with_rpath... not found',"
        err "the Nix wrapper may be filtering PKG_CONFIG_PATH."
        err "This script tries to work around this automatically, but"
        err "the workaround may have failed. Check the output above."
      fi
      exit 1
    fi
  fi
}

# --------------------------------------------------------------------------
# Test
# --------------------------------------------------------------------------

do_test() {
  log "Running specs..."

  local missing=()
  for spec in "${SPEC_FILES[@]}"; do
    if [ ! -f "$spec" ]; then
      missing+=("$spec")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    err "Spec file(s) not found: ${missing[*]}"
    exit 1
  fi

  bundle exec rspec "${SPEC_FILES[@]}" 2>&1 | tee /tmp/libdatadog_native_specs.log | grep -E 'Pending:|Failures:|Finished' -A 99

  local rspec_exit=${PIPESTATUS[0]}
  if [ "$rspec_exit" -eq 0 ]; then
    log "All specs passed."
  else
    err "Specs failed (exit ${rspec_exit}).  Full output: /tmp/libdatadog_native_specs.log"
    exit "$rspec_exit"
  fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

case "${1:-}" in
  --compile-only)
    do_compile
    ;;
  --test-only)
    do_test
    ;;
  *)
    do_compile
    echo
    do_test
    ;;
esac
