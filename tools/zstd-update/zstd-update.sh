#!/usr/bin/env bash
# Updates the profiler's vendored zstd.c from a pinned GitHub release. Downloads
# and extracts the source, verifies the upstream zstd-in.c's SHA-256 checksum,
# then generates the library using our local zstd-in.c. Temporary files are cleaned up on exit.
set -euo pipefail

readonly ZSTD_VERSION="v1.6.0"
readonly EXPECTED_CHECKSUM="238606d9ad2cb4f40063a7def25395f31302da31c0e09727e20af0d204f87721"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
output_dir="$repo_root/ext/datadog_profiling_native_extension/miteruby/pprof"
output_path="$output_dir/zstd.c"
license_path="$output_dir/zstd.LICENSE.txt"

temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

archive_name="zstd-${ZSTD_VERSION#v}.tar.gz"
printf 'Downloading zstd %s...\n' "$ZSTD_VERSION"
curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/meta/zstd/releases/download/$ZSTD_VERSION/$archive_name" \
  -o "$temp_dir/$archive_name"
tar -xzf "$temp_dir/$archive_name" -C "$temp_dir"

source_dir="$temp_dir/zstd-${ZSTD_VERSION#v}"
upstream_template_path="$source_dir/build/single_file_libs/zstd-in.c"
actual_checksum="$(python3 -c '
import hashlib
import sys

with open(sys.argv[1], "rb") as template:
    print(hashlib.sha256(template.read()).hexdigest())
' "$upstream_template_path")"

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
    -x common/zstd_trace.h -x compress/zstdmt_compress.h \
    -o "$temp_dir/zstd.c" "$script_dir/zstd-in.c"
)

# @ivoanjo: zstd includes freestanding_lib to adapt its sources for environments with custom runtime dependencies; we reuse its partial preprocessor to remove stuff that's being ifdef'd out.
# @ivoanjo: Upstream xxhash.h defines XXH_NO_XXH3, so it was already going to be ignored. We additionally strip multithreading support and compressor code that was being disabled in zstd-in.c.
(
  cd -- "$source_dir/contrib/freestanding_lib"
  python3 - "$temp_dir/zstd.c" > /dev/null <<'PY'
import sys, freestanding
freestanding.PartialPreprocessor(
    defs=[(name, None) for name in ["XXH_NO_XXH3", "ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR", "ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR", "ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR", "ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR", "ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR", "ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR", "ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR"]],
    replaces=[], undefs=["ZSTD_MULTITHREAD"]).preprocess(sys.argv[1])
PY
)

# @ivoanjo: Strip standalone comments, trailing block comments and extra blank lines to reduce zstd.c size.
ruby -0777 -i -pe 'gsub(%r{^[ \t]*/\*.*?\*/|(?<=[,;])[ \t]+/\*(?:(?!\*/).)*\*/[ \t]*$}m) { |c| c if c =~ /copyright|license|SPDX|@ivoanjo|\*{4} \w+ inlining /i }; gsub(/\n([ \t]*\n){2,}/, "\n\n")' "$temp_dir/zstd.c"

# @ivoanjo: Trim trailing whitespace except after a backslash, and replace each group of eight leading spaces with a tab.
# @ivoanjo: Preserve indentation on continued lines, where it can be part of a string literal.
ruby -0777 -i -pe 'gsub(/(?<![\\ \t])[ \t]+$/, ""); gsub(/(?<!\\\n)^(?: {8})+/) { |spaces| "\t" * (spaces.size / 8) }' "$temp_dir/zstd.c"

install -m 644 "$temp_dir/zstd.c" "$output_path"
install -m 644 "$source_dir/LICENSE" "$license_path"
printf 'Updated %s\n' "$output_path" "$license_path"
