#!/usr/bin/env bash
# Updates the profiler's vendored zstd.c from a pinned GitHub release. Downloads
# and extracts the source, verifies zstd-in.c's SHA-256 checksum, then generates
# the single-file library. Temporary downloads and sources are cleaned up on exit.
set -euo pipefail

readonly ZSTD_VERSION="v1.5.7"
readonly EXPECTED_CHECKSUM="238606d9ad2cb4f40063a7def25395f31302da31c0e09727e20af0d204f87721"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
output_path="$repo_root/ext/datadog_profiling_native_extension/miteruby/pprof/zstd.c"

temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

archive_name="zstd-${ZSTD_VERSION#v}.tar.gz"
printf 'Downloading zstd %s...\n' "$ZSTD_VERSION"
curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/facebook/zstd/releases/download/$ZSTD_VERSION/$archive_name" \
  -o "$temp_dir/$archive_name"
tar -xzf "$temp_dir/$archive_name" -C "$temp_dir"

source_dir="$temp_dir/zstd-${ZSTD_VERSION#v}"
template_path="$source_dir/build/single_file_libs/zstd-in.c"
actual_checksum="$(python3 -c '
import hashlib
import sys

with open(sys.argv[1], "rb") as template:
    print(hashlib.sha256(template.read()).hexdigest())
' "$template_path")"

if [[ "$actual_checksum" != "$EXPECTED_CHECKSUM" ]]; then
  printf 'zstd-in.c SHA-256 mismatch: expected %s, got %s\n' \
    "$EXPECTED_CHECKSUM" "$actual_checksum" >&2
  printf '%s\n' \
    'Upstream configuration file changed. Diff our local one with the upstream version, incorporate any changes, and update the hash.' >&2
  exit 1
fi

printf 'Checksum verified. Generating zstd.c...\n'
(
  cd -- "$source_dir/build/single_file_libs"
  python3 combine.py -r ../../lib -x legacy/zstd_legacy.h \
    -o "$temp_dir/zstd.c" zstd-in.c
)

install -m 644 "$temp_dir/zstd.c" "$output_path"
printf 'Updated %s\n' "$output_path"
