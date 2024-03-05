# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'pry'
require_relative 'dogstatsd_reporter'

require 'libdatadog'

puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"

# This benchmark measures the performance of sampling + serializing memory profiles. It enables us to evaluate changes to
# the profiler and/or libdatadog that may impact both individual samples, as well as samples over time.
#
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

class ProfilerMemorySampleSerializeBenchmark
  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: false,
      alloc_samples_enabled: true,
      heap_samples_enabled: false,
      heap_size_enabled: false,
      heap_sample_every: 1,
      timeline_enabled: false,
    )
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
        suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_memory_sample_serialize')
      )

      x.report("sample+serialize #{ENV['CONFIG']}") do
        samples_per_second = 100
        simulate_seconds = 60

        (samples_per_second * simulate_seconds).times do |i|
          sample_object(@recorder, i % 400)
        end

        @recorder.serialize
        nil
      end

      x.save! 'profiler_memory_sample_serialize-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize
  end

  def run_forever
    loop do
      1000.times do |i|
        sample_object(@recorder, i % 400)
      end
      @recorder.serialize
      print '.'
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerMemorySampleSerializeBenchmark.new.instance_exec do
  create_profiler
  if ARGV.include?('--forever')
    run_forever
  else
    run_benchmark
  end
end
