# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'pry'
require_relative 'dogstatsd_reporter'

require 'libdatadog'

puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"

# This benchmark measures the performance of sampling + serializing profiles. It enables us to evaluate changes to
# the profiler and/or libdatadog that may impact both individual samples, as well as samples over time (e.g. timeline).

class ProfilerSampleSerializeBenchmark
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler
    timeline_enabled = ENV['TIMELINE'] == 'true'
    @recorder = Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: true,
      alloc_samples_enabled: false,
      heap_samples_enabled: false,
      heap_size_enabled: false,
      heap_sample_every: 1,
      timeline_enabled: timeline_enabled,
    )
    @collector = Datadog::Profiling::Collectors::ThreadContext.new(
      recorder: @recorder, max_frames: 400, tracer: nil, endpoint_collection_enabled: false, timeline_enabled: timeline_enabled
    )
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
        suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_sample_serialize')
      )

      x.report("sample #{ENV['CONFIG']} timeline=#{ENV['TIMELINE'] == 'true'}") do
        samples_per_second = 100
        simulate_seconds = 60

        (samples_per_second * simulate_seconds).times do
          Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
        end

        @recorder.serialize
        nil
      end

      x.save! 'profiler_sample_serialize-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize
  end

  def run_forever
    while true
      1000.times do
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
      end
      @recorder.serialize
      print '.'
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerSampleSerializeBenchmark.new.instance_exec do
  create_profiler
  10.times { Thread.new { sleep } }
  if ARGV.include?('--forever')
    run_forever
  else
    run_benchmark
  end
end
