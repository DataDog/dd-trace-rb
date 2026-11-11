# frozen_string_literal: true

# Timing harness for the Kafka DSM workload (kafka_dsm.rb).
#
# Ruby stand-in for `dotnet timeit --count 25 --warmup 5` / Python's
# `run_timeit.py`. Runs the workload for a fixed number of warmup + timed
# iterations in-process (so the tracer, when enabled, stays active across all
# iterations), then emits a JSON artifact in the shape
# benchmarking-platform's `steps/compare-results.py` expects:
#
#   [
#     {
#       "median": <median duration ms>,
#       "metrics": {
#         "process.internal_duration_ms.median": <ms>,
#         "process.internal_duration_ms.std_err": <ms>,
#         "process.iteration_wall_ms.median": <ms>,
#         "process.rss_bytes.median": <bytes>,
#         "phase.produce_ms.median": <ms>,
#         "phase.consume_ms.median": <ms>,
#         "config.commit_every": <COMMIT_EVERY>
#       },
#       "name": <EXPERIMENT_NAME>,
#       "warmUpCount": <WARMUP>,
#       "count": <COUNT>,
#       "data": [
#         {
#           "status": "Passed",
#           "metrics": {
#             "process.internal_duration_ms": <ms>,
#             "process.corrected_duration_ms": <ms, iteration wall time>,
#             "runtime.dotnet.mem.committed": <bytes, process RSS>
#           }
#         },
#         ... one per timed iteration
#       ]
#     }
#   ]
#
# `data` is for the platform's steps/convert-to-common-format.sh: bp-analyzer's
# TimeItSharp converter reads only per-iteration values from it, under
# TimeItSharp's metric names (it maps runtime.dotnet.mem.committed to RSS,
# whatever the runtime), and fails on a file without it.
#
# Duration is produce_ms + consume_ms per iteration (setup/teardown --
# client construction, group join, close -- excluded); the whole-iteration
# wall time is kept separately as process.iteration_wall_ms, for context
# only. The memory metric is process RSS,
# sampled via the get_process_mem gem (Ruby analog of Python's
# psutil.Process().memory_info().rss). Medians are used for robustness
# against outliers, matching the .NET and Python gates.

require "json"
require "get_process_mem"

# Both of these must be loaded before datadog. dd-trace-rb's
# Kafka::Integration.loaded? requires ::Kafka *and*
# ::ActiveSupport::Notifications to already be defined, and the patcher applies
# its DSM monkey patches under `defined?(::Kafka::Producer)` guards (see
# contrib/kafka/{integration,patcher}.rb). Requiring datadog first makes the
# whole integration silently no-op, which reads as "DSM is free" rather than
# as a broken benchmark.
# `active_support` itself must come first: from ActiveSupport 7 on,
# Notifications.registry reads ActiveSupport::IsolatedExecutionState, which
# requiring only active_support/notifications does not autoload (NameError).
require "active_support"
require "active_support/notifications"
require "kafka"

if ENV["ENABLE_TRACER"] == "true"
  require "datadog/auto_instrument"

  # Fail loudly rather than reporting a meaningless PASS if patching didn't take.
  patched = ::Kafka::Producer.ancestors.any? { |m| m.name.to_s.start_with?("Datadog") }
  raise "kafka producer was not patched by datadog -- would measure nothing" unless patched
end

require_relative "kafka_dsm"

# Fail unless DSM's actual state matches DD_DATA_STREAMS_ENABLED, e.g. when
# the libdatadog_api extension is missing and DSM silently stays off.
def assert_data_streams_state!
  return unless ENV["ENABLE_TRACER"] == "true"

  raw = ENV["DD_DATA_STREAMS_ENABLED"]
  expected = %w[true 1].include?(raw.to_s.strip.downcase)
  actual = Datadog::DataStreams.enabled?
  return if actual == expected

  ext = Datadog::Core::LIBDATADOG_API_FAILURE || "loaded"
  raise "DD_DATA_STREAMS_ENABLED=#{raw.inspect} but Datadog::DataStreams.enabled? is #{actual} " \
    "(libdatadog_api: #{ext}) -- would measure the wrong scenario"
end

def median(values)
  sorted = values.sort
  n = sorted.size
  mid = n / 2
  n.even? ? (sorted[mid - 1] + sorted[mid]) / 2.0 : sorted[mid]
end

def std_err(values)
  return 0.0 if values.size <= 1

  mean = values.sum / values.size.to_f
  variance = values.sum { |v| (v - mean)**2 } / (values.size - 1)
  Math.sqrt(variance) / Math.sqrt(values.size)
end

def main
  # Validated up front so a bad value fails before any warmup run.
  warmup = integer_from_env("WARMUP", 5, 0)
  count = integer_from_env("COUNT", 25, 1)
  commit_every = commit_every_from_env
  output_path = ENV.fetch("TIMEIT_OUTPUT", "results.json")

  process_mem = GetProcessMem.new
  run_id = 0

  warmup.times do
    run_benchmark(run_id, commit_every: commit_every)
    run_id += 1
  end
  assert_data_streams_state!

  durations_ms = []
  iteration_wall_ms = []
  rss_bytes = []
  produce_ms = []
  consume_ms = []

  count.times do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    phases = run_benchmark(run_id, commit_every: commit_every)
    iteration_wall_ms << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    durations_ms << phases[:produce_ms] + phases[:consume_ms]
    rss_bytes << process_mem.bytes.to_i
    produce_ms << phases[:produce_ms]
    consume_ms << phases[:consume_ms]
    run_id += 1
  end

  duration_median = median(durations_ms)
  duration_std_err = std_err(durations_ms)
  iteration_wall_median = median(iteration_wall_ms)
  rss_median = median(rss_bytes)
  produce_median = median(produce_ms)
  consume_median = median(consume_ms)

  result = [
    {
      "median" => duration_median,
      "metrics" => {
        "process.internal_duration_ms.median" => duration_median,
        "process.internal_duration_ms.std_err" => duration_std_err,
        "process.iteration_wall_ms.median" => iteration_wall_median,
        "process.rss_bytes.median" => rss_median,
        "phase.produce_ms.median" => produce_median,
        "phase.consume_ms.median" => consume_median,
        "config.commit_every" => commit_every,
      },
      "name" => ENV.fetch("EXPERIMENT_NAME", "kafka_dsm"),
      "warmUpCount" => warmup,
      "count" => count,
      "data" => durations_ms.each_index.map do |i|
        {
          "status" => "Passed",
          "metrics" => {
            "process.internal_duration_ms" => durations_ms[i],
            "process.corrected_duration_ms" => iteration_wall_ms[i],
            "runtime.dotnet.mem.committed" => rss_bytes[i],
          },
        }
      end,
    },
  ]

  File.write(output_path, JSON.pretty_generate(result))

  printf(
    "Duration median: %.3f ms (+/- %.3f) | Iteration wall median: %.3f ms | RSS median: %.2f MB | " \
    "produce median: %.3f ms | consume+commit median: %.3f ms | runs: %d (warmup %d) | commit every %d\n",
    duration_median,
    duration_std_err,
    iteration_wall_median,
    rss_median / 1_000_000.0,
    produce_median,
    consume_median,
    count,
    warmup,
    commit_every,
  )
end

main if __FILE__ == $PROGRAM_NAME
