#!/usr/bin/env bash
set -euo pipefail

# This small script uses the nanopb tools to go from the `pprof_fragments.proto` file
# and generate the `pprof_fragments.pb.c`/`pprof_fragments.pb.h` files.
#
# These are then used by the profiler to serialize profiles (see `PprofFragmentsEncoder.md`
# for details on how they're used)

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
  --nanopb_out="--c-style,--library-include-format=quote:$pprof_dir" \
  "$pprof_dir/pprof_fragments.proto"

# @ivoanjo: protobuf stuff is internal to miteruby -- nothing else should use it. We want to mark every declaration in it as
# MITERUBY_INTERNAL, so that we can make them static and optimize it better for the miteruby unity build. So we have
# a bit of code here to help us inject MITERUBY_INTERNAL in front of pprof fragments declarations.
# (Yes this is a bit of black magic, yet I'll point out we're operating on C sources so we can trivially inspect the
# before/after and make sure this is correct.)
ruby -i -pe 'sub(/^extern (?=const pb_msgdesc_t )/, "MITERUBY_INTERNAL ")' "$pprof_dir/pprof_fragments.pb.h"

printf 'Updated pprof_fragments.pb.c and pprof_fragments.pb.h in %s\n' "$pprof_dir"
