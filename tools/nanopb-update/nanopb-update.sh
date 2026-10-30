#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <path-to-protoc> <path-to-protoc-gen-nanopb>\n' "$0" >&2
  printf '%s\n' \
    'Use the protoc and protoc-gen-nanopb executables bundled with nanopb.' \
    '(Get it from https://github.com/nanopb/nanopb )' >&2
  exit 1
fi

protoc_path="$1"
plugin_path="$2"
for executable in "$protoc_path" "$plugin_path"; do
  if [[ ! -f "$executable" || ! -x "$executable" ]]; then
    printf 'Not an executable file: %s\n' "$executable" >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
pprof_dir="$repo_root/ext/datadog_profiling_native_extension/miteruby/pprof"

"$protoc_path" \
  --proto_path="$pprof_dir" \
  --plugin="protoc-gen-nanopb=$plugin_path" \
  --nanopb_out="--c-style:$pprof_dir" \
  "$pprof_dir/pprof_fragments.proto"

printf 'Updated pprof_fragments.pb.c and pprof_fragments.pb.h in %s\n' "$pprof_dir"
