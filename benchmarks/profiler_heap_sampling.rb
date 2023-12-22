# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'pry'
require_relative 'dogstatsd_reporter'

METRIC_VALUES = { 'cpu-time' => 0, 'cpu-samples' => 0, 'wall-time' => 0, 'alloc-samples' => 1, 'timeline' => 0 }.freeze
OBJECT_CLASS = 'object'.freeze

def sample_object(recorder, depth = 0)
  if depth <= 0
    Datadog::Profiling::StackRecorder::Testing._native_track_object(
      recorder,
      Object.new,
      1,
      OBJECT_CLASS,
    )
    Datadog::Profiling::Collectors::Stack::Testing._native_sample(
      Thread.current,
      recorder,
      METRIC_VALUES,
      [],
      [],
      400,
      false
    )
  else
    sample_object(recorder, depth - 1)
  end
end

# This benchmark measures the performance of the sampling operations with different flavours of heap profiling
# with single stacks
Benchmark.ips do |x|
  benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
  x.config(
    **benchmark_time,
    suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_heap_sampling')
  )

  recorder_without_heap = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: false,
    heap_samples_enabled: false,
    heap_size_enabled: false,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_with_heap = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  x.report('no heap - single stack') do
    sample_object(recorder_without_heap)
  end

  x.report('heap - single stack') do
    sample_object(recorder_with_heap)
  end

  x.save! 'profiler-heap-sampling-results-single-stack.json' unless VALIDATE_BENCHMARK_MODE
  x.compare!
end

# This benchmark measures the performance of the sampling operations with different flavours of heap profiling
# with many stacks
Benchmark.ips do |x|
  benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
  x.config(
    **benchmark_time,
    suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_heap_sampling_many_stacks')
  )

  recorder_without_heap = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: false,
    heap_samples_enabled: false,
    heap_size_enabled: false,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_with_heap = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  x.report('no heap - many stacks') do |times|
    i = 0
    while i < times
      sample_object(recorder_without_heap, i % 400)
      i += 1
    end
  end

  x.report('heap - many stacks') do |times|
    i = 0
    while i < times
      sample_object(recorder_with_heap, i % 400)
      i += 1
    end
  end

  x.save! 'profiler-heap-sampling-many-stacks-results.json' unless VALIDATE_BENCHMARK_MODE
  x.compare!
end

# This benchmark measures the performance of the sampling operations with different heap profiling sampling levels
Benchmark.ips do |x|
  benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
  x.config(
    **benchmark_time,
    suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_heap_sampling_rates')
  )

  recorder_heap_sampling_1 = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: false,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_heap_sampling_10 = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 10,
    timeline_enabled: false,
  )

  recorder_heap_sampling_100 = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 100,
    timeline_enabled: false,
  )

  x.report('heap profiling - sample_rate=1') do |times|
    i = 0
    while i < times
      sample_object(recorder_heap_sampling_1, i % 400)
      i += 1
    end
  end

  x.report('heap profiling - sample_rate=10') do |times|
    i = 0
    while i < times
      sample_object(recorder_heap_sampling_10, i % 400)
      i += 1
    end
  end

  x.report('heap profiling - sample_rate=100') do |times|
    i = 0
    while i < times
      sample_object(recorder_heap_sampling_100, i % 400)
      i += 1
    end
  end

  x.save! 'profiler-heap-sampling-rates-results.json' unless VALIDATE_BENCHMARK_MODE
  x.compare!
end
