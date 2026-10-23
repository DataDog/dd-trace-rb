#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

benchmark='10.times { p Benchmark.realtime { sum = 0; 150_000_000.times { |i| sum = (sum + i) % 77 } } }'
ruby_args=(-v --yjit --yjit-call-threshold=2 -rbenchmark -e "$benchmark")

printf '\nBaseline (no profiler)\n'
ruby "${ruby_args[@]}"

printf '\nRegular Datadog profiler, telemetry disabled\n'
env MITERUBY=false \
  DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true \
  DD_PROFILING_ENABLED=true \
  DD_INSTRUMENTATION_TELEMETRY_ENABLED=false \
  DD_SERVICE=benoit-testing \
  bundle exec ddprofrb exec ruby "${ruby_args[@]}"

## @ivoanjo: Telemetry also disturbs this benchmark, since the loop runs for very long. Since right now we're mostly
## worried with profiler impact, we can investigate this later.
# printf '\nDatadog profiler with miteruby, telemetry enabled\n'
# env MITERUBY=true \
#   DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true \
#   DD_PROFILING_ENABLED=true \
#   DD_INSTRUMENTATION_TELEMETRY_ENABLED=true \
#   DD_SERVICE=benoit-testing \
#   bundle exec ddprofrb exec ruby "${ruby_args[@]}"

printf '\nDatadog profiler with miteruby, telemetry disabled\n'
env MITERUBY=true \
  DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true \
  DD_PROFILING_ENABLED=true \
  DD_INSTRUMENTATION_TELEMETRY_ENABLED=false \
  DD_SERVICE=benoit-testing \
  bundle exec ddprofrb exec ruby "${ruby_args[@]}"
