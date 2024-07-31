#!/bin/sh

# This script is invoked by benchmarking-platform shell scripts
# to run all of the benchmarks defined in the tracer.

set -ex

for file in \
  `dirname "$0"`/gem_loading.rb \
  `dirname "$0"`/profiler_allocation.rb \
  `dirname "$0"`/profiler_gc.rb \
  `dirname "$0"`/profiler_hold_resume_interruptions.rb \
  `dirname "$0"`/profiler_http_transport.rb \
  `dirname "$0"`/profiler_memory_sample_serialize.rb \
  `dirname "$0"`/profiler_sample_loop_v2.rb \
  `dirname "$0"`/profiler_sample_serialize.rb \
  `dirname "$0"`/tracing_trace.rb;
do
  bundle exec ruby "$file"
done
