#!/bin/sh

# This script is invoked by benchmarking-platform shell scripts
# to run all of the benchmarks defined in the tracer.

set -ex

SCRIPT_DIR="$(dirname "$0")"

nproc

# Print the CPU affinity of the current process
taskset -pc $$

# Clean and create directory for completed runs
rm -rf completed_runs
mkdir completed_runs

for run in 1 2 3 4 5; do
  for file in \
    "$SCRIPT_DIR/error_tracking_simple.rb" \
    "$SCRIPT_DIR/di_instrument.rb" \
    "$SCRIPT_DIR/library_gem_loading.rb" \
    "$SCRIPT_DIR/profiling_allocation.rb" \
    "$SCRIPT_DIR/profiling_gc.rb" \
    "$SCRIPT_DIR/profiling_hold_resume_interruptions.rb" \
    "$SCRIPT_DIR/profiling_http_transport.rb" \
    "$SCRIPT_DIR/profiling_memory_sample_serialize.rb" \
    "$SCRIPT_DIR/profiling_sample_loop_v2.rb" \
    "$SCRIPT_DIR/profiling_sample_serialize.rb" \
    "$SCRIPT_DIR/profiling_sample_gvl.rb" \
    "$SCRIPT_DIR/profiling_string_storage_intern.rb" \
    "$SCRIPT_DIR/tracing_trace.rb";
  do
    taskset -c 24-27 bundle exec ruby "$file"
  done
  # Move results to subdirectory with run ID to avoid re-matching in next iteration
  for f in *-results.json; do
    [ -e "$f" ] || continue
    mv "$f" "completed_runs/${f%-results.json}--${run}--results.json"
  done
done

# Move all results back to cwd for run-benchmarks.sh to find
mv completed_runs/* .
rmdir completed_runs
