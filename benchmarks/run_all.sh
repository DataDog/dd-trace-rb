#!/bin/sh

# This script is invoked by benchmarking-platform shell scripts
# to run all of the benchmarks defined in the tracer.

set -ex

for file in \
  `dirname "$0"`/tracing_trace.rb \
  `dirname "$0"`/gem_loading.rb \
  `dirname "$0"`/profiler_*.rb;
do
  bundle exec ruby "$file"
done
