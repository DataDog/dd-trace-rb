#!/usr/bin/env bash
set -euo pipefail

readonly NANOPB_VERSION=0.4.9.2

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
pprof_dir="$repo_root/ext/datadog_profiling_native_extension/miteruby/pprof"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT

printf 'Downloading nanopb %s...\n' "$NANOPB_VERSION"
archive="$temp_dir/nanopb.tar.gz"
curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/nanopb/nanopb/archive/refs/tags/$NANOPB_VERSION.tar.gz" -o "$archive"
tar -xzf "$archive" -C "$temp_dir"
cd -- "$temp_dir/nanopb-$NANOPB_VERSION"

install -m 644 pb.h pb_common.h pb_common.c pb_encode.h pb_encode.c "$pprof_dir/"
install -m 644 LICENSE.txt "$pprof_dir/nanopb.LICENSE.txt"
printf 'Updated nanopb runtime in %s\n' "$pprof_dir"
