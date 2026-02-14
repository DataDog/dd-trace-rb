#!/usr/bin/env bash

# This script is invoked by benchmarking-platform shell scripts
# to run all of the benchmarks defined in the tracer.

set -ex

SCRIPT_DIR="$(dirname "$0")"

# --- Helper functions ---

parse_cpu_affinity() {
  # Parses CPU_AFFINITY (e.g., "24-47" or "24-31,40-47") into space-separated list
  local affinity=$1
  local result=""
  IFS=',' read -ra parts <<< "$affinity"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for ((i=BASH_REMATCH[1]; i<=BASH_REMATCH[2]; i++)); do
        result+="$i "
      done
    else
      result+="$part "
    fi
  done
  echo "${result% }"  # Trim trailing space
}

get_cpus_for_benchmark() {
  # Returns comma-separated CPU list for benchmark at given index
  local cpu_ids_str=$1
  local idx=$2
  local cpus_per_benchmark=$3

  local -a cpu_ids
  read -ra cpu_ids <<< "$cpu_ids_str"

  local start=$((idx * cpus_per_benchmark))
  local cpu_list=""
  for ((j=0; j<cpus_per_benchmark; j++)); do
    [ -n "$cpu_list" ] && cpu_list+=","
    cpu_list+="${cpu_ids[$((start + j))]}"
  done
  echo "$cpu_list"
}

validate_inputs() {
  local cpu_ids_str=$1
  local benchmarks=$2
  local cpus_per_benchmark=$3

  if [ -z "$benchmarks" ]; then
    echo "ERROR: BENCHMARKS env var not set"
    exit 1
  fi

  local -a cpu_ids
  read -ra cpu_ids <<< "$cpu_ids_str"

  if [ ${#cpu_ids[@]} -eq 0 ]; then
    echo "ERROR: CPU_AFFINITY env var not set or empty"
    exit 1
  fi

  local -a benchmark_array
  read -ra benchmark_array <<< "$benchmarks"
  local benchmark_count=${#benchmark_array[@]}

  local cpus_needed=$((benchmark_count * cpus_per_benchmark))
  local cpus_available=${#cpu_ids[@]}

  if [ "$cpus_needed" -gt "$cpus_available" ]; then
    echo "ERROR: Need $cpus_needed CPUs ($benchmark_count benchmarks × $cpus_per_benchmark) but only $cpus_available available"
    exit 1
  fi
}

run_benchmarks_parallel() {
  local cpu_ids_str=$1
  local benchmarks=$2
  local cpus_per_benchmark=$3

  local -a benchmark_array
  read -ra benchmark_array <<< "$benchmarks"

  local idx=0
  for file in "${benchmark_array[@]}"; do
    local cpus
    cpus=$(get_cpus_for_benchmark "$cpu_ids_str" "$idx" "$cpus_per_benchmark")
    taskset -c "$cpus" bundle exec ruby "$SCRIPT_DIR/$file" &
    idx=$((idx + 1))
  done
  wait
}

collect_results() {
  local run=$1
  local output_dir=$2
  for f in *-results.json; do
    [ -e "$f" ] || continue
    mv "$f" "${output_dir}/${f%-results.json}--${run}--results.json"
  done
}

cpus_per_benchmark=${CPUS_PER_BENCHMARK:-2}
repetitions=${REPETITIONS:-10}
cpu_ids_str=$(parse_cpu_affinity "$CPU_AFFINITY")

validate_inputs "$cpu_ids_str" "$BENCHMARKS" "$cpus_per_benchmark"

rm -rf completed_runs && mkdir completed_runs

for run in $(seq 1 "$repetitions"); do
  run_benchmarks_parallel "$cpu_ids_str" "$BENCHMARKS" "$cpus_per_benchmark"
  collect_results "$run" "completed_runs"
done

mv completed_runs/* .
rmdir completed_runs
