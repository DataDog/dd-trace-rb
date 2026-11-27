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

# nanopb-update-pprof-fragments.sh adds MITERUBY_INTERNAL to the descriptor declarations in pprof_fragments.pb.h.
# PB_BIND in pb.h generates their definitions, so we need to add MITERUBY_INTERNAL here too or the linkage will conflict.
ruby -i -pe 'sub(/^(    )(?=const pb_msgdesc_t structname ## _msg =)/, "\\1MITERUBY_INTERNAL ")' pb.h

install -m 644 pb.h pb_common.h pb_common.c pb_encode.h pb_encode.c "$pprof_dir/"
install -m 644 LICENSE.txt "$pprof_dir/nanopb.LICENSE.txt"
printf 'Updated nanopb runtime in %s\n' "$pprof_dir"
