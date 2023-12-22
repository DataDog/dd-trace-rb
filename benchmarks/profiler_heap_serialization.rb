# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'pry'
require_relative 'dogstatsd_reporter'

RANDOM = Random.new
METRIC_VALUES = { 'cpu-time' => 0, 'cpu-samples' => 0, 'wall-time' => 0, 'alloc-samples' => 1, 'timeline' => 0 }.freeze

def sample_object(recorder, obj, depth = 0)
  if depth <= 0
    Datadog::Profiling::StackRecorder::Testing._native_track_object(
      recorder,
      obj,
      1,
      obj.class.name,
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
    sample_object(recorder, obj, depth - 1)
  end
end

def random_value(depth = 0)
  case [:array, :hash, :string, :number, :object].sample
  when :array
    random_array(depth)
  when :hash
    random_hash(depth)
  when :string
    RANDOM.bytes(rand(0..50))
  when :number
    rand(-1_000_000_000_000..1_000_000_000_000)
  when :object
    BenchmarkObject.new(depth)
  end
end

def create_benchmark_live_objects(num_objects: 1_000_000)
  live_objects = []

  num_objects.times { live_objects << random_object }
end

def random_array(depth)
  num_entries = rand(0..(100 / (10**depth)))
  Array.new(num_entries) { random_value(depth + 1) }
end

def random_hash(depth)
  num_entries = rand(0..(100 / (10**depth)))
  Array.new(num_entries) { [random_value(depth + 1).freeze, random_value(depth + 1)] }.to_h
end

class BenchmarkObject < Object
  def initialize(depth)
    num_fields = rand(0..(100 / (10**depth)))
    obj = self

    num_fields.times { |i| obj.instance_variable_set("@field#{i}".to_sym, random_value(depth + 1)) }
  end
end

# This benchmark measures the performance of different flavours of heap profiling
Benchmark.ips do |x|
  benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
  x.config(
    **benchmark_time,
    suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_heap_serialization')
  )

  recorder_without_heap = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: false,
    heap_samples_enabled: false,
    heap_size_enabled: false,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_with_heap_samples_only = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: false,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_with_full_heap = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  live_objects = Array.new(VALIDATE_BENCHMARK_MODE ? 100 : 10_000) { BenchmarkObject.new(0) }

  live_objects.each_with_index do |obj, _i|
    sample_object(recorder_without_heap, obj)
    sample_object(recorder_with_heap_samples_only, obj)
    sample_object(recorder_with_full_heap, obj)
  end

  x.report('full serialization without heap profiling') do
    recorder_without_heap.serialize!
  end

  x.report('heap sampling serialization preparation - samples') do
    Datadog::Profiling::StackRecorder::Testing._native_prepare_heap_serialization(recorder_with_heap_samples_only)
    Datadog::Profiling::StackRecorder::Testing._native_finish_heap_serialization(recorder_with_heap_samples_only)
  end

  x.report('heap sampling serialization preparation - samples+size') do
    Datadog::Profiling::StackRecorder::Testing._native_prepare_heap_serialization(recorder_with_full_heap)
    Datadog::Profiling::StackRecorder::Testing._native_finish_heap_serialization(recorder_with_full_heap)
  end

  x.report('full serialization with heap profiling - samples') do
    recorder_with_heap_samples_only.serialize!
  end

  x.report('full serialization with heap profiling - samples+size') do
    recorder_with_full_heap.serialize!
  end

  x.save! 'profiler-heap-serialization-results.json' unless VALIDATE_BENCHMARK_MODE
  x.compare!
end

# This benchmark measures the effect of stack variety on heap serialization.
Benchmark.ips do |x|
  benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
  x.config(
    **benchmark_time,
    suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_heap_serialization_stacks')
  )

  recorder_single_stack = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_many_stacks = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  live_objects = Array.new(VALIDATE_BENCHMARK_MODE ? 100 : 10_000) { BenchmarkObject.new(0) }

  live_objects.each_with_index do |obj, i|
    sample_object(recorder_single_stack, obj)
    depth = i % 400
    sample_object(recorder_many_stacks, obj, depth)
  end

  x.report('heap profiling serialization - single stack') do
    recorder_single_stack.serialize!
  end

  x.report('heap profiling serialization - many stacks') do
    recorder_many_stacks.serialize!
  end

  x.save! 'profiler-heap-serialization-stacks-results.json' unless VALIDATE_BENCHMARK_MODE
  x.compare!
end

# This benchmark measures the effect of heap sampling on heap serialization.
Benchmark.ips do |x|
  benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
  x.config(
    **benchmark_time,
    suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_heap_serialization_sampling')
  )

  recorder_with_full_heap_and_sampling_1 = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  )

  recorder_with_full_heap_and_sampling_10 = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 10,
    timeline_enabled: false,
  )

  recorder_with_full_heap_and_sampling_100 = Datadog::Profiling::StackRecorder.new(
    cpu_time_enabled: false,
    alloc_samples_enabled: true,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 100,
    timeline_enabled: false,
  )

  live_objects = Array.new(VALIDATE_BENCHMARK_MODE ? 100 : 10_000) { BenchmarkObject.new(0) }

  live_objects.each_with_index do |obj, i|
    depth = i % 400
    sample_object(recorder_with_full_heap_and_sampling_1, obj, depth)
    sample_object(recorder_with_full_heap_and_sampling_10, obj, depth)
    sample_object(recorder_with_full_heap_and_sampling_100, obj, depth)
  end

  x.report('heap profiling serialization with sampling rate of 1') do
    recorder_with_full_heap_and_sampling_1.serialize!
  end

  x.report('heap profiling serialization with sampling rate of 10') do
    recorder_with_full_heap_and_sampling_10.serialize!
  end

  x.report('heap profiling serialization with sampling rate of 100') do
    recorder_with_full_heap_and_sampling_100.serialize!
  end

  x.save! 'profiler-heap-serialization-sampling-results.json' unless VALIDATE_BENCHMARK_MODE
  x.compare!
end
