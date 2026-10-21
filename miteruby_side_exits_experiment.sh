#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

benchmark='10.times { p Benchmark.realtime { sum = 0; 150_000_000.times { |i| sum = (sum + i) % 77 } } }'
ruby_args=(-v --yjit --yjit-call-threshold=2 -rbenchmark -e "$benchmark")

printf '\nBaseline\n'
ruby "${ruby_args[@]}"

printf '\nDatadog profiler\n'
env -u MITERUBY \
  DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true \
  DD_PROFILING_ENABLED=true \
  DD_SERVICE=benoit-testing \
  bundle exec ddprofrb exec ruby "${ruby_args[@]}"

printf '\nDatadog profiler with miteruby\n'
env MITERUBY=true \
  DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true \
  DD_PROFILING_ENABLED=true \
  DD_SERVICE=benoit-testing \
  bundle exec ddprofrb exec ruby "${ruby_args[@]}"
