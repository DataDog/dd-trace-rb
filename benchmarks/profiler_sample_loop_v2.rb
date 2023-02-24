# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'pry'
require_relative 'dogstatsd_reporter'

# This benchmark measures the performance of the main stack sampling loop of the profiler

class ProfilerSampleLoopBenchmark
  # This is needed because we're directly invoking the CpuAndWallTime collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.new(cpu_time_enabled: true, alloc_samples_enabled: true)
    @collector = Datadog::Profiling::Collectors::CpuAndWallTime.new(recorder: @recorder, max_frames: 400, tracer: nil)
  end

  def thread_with_very_deep_stack(depth: 500)
    deep_stack = proc do |n|
      if n > 0
        deep_stack.call(n - 1)
      else
        sleep
      end
    end

    Thread.new { deep_stack.call(depth) }.tap { |t| t.name = "Deep stack #{depth}" }
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(**benchmark_time, suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_sample_loop_v2'))

      x.report("stack collector #{ENV['CONFIG']}") do
        Datadog::Profiling::Collectors::CpuAndWallTime::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
      end

      x.save! 'profiler-sample-loop-v2-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize
  end

  def run_forever
    while true
      1000.times { Datadog::Profiling::Collectors::CpuAndWallTime::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD) }
      @recorder.serialize
      print '.'
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerSampleLoopBenchmark.new.instance_exec do
  create_profiler
  4.times { thread_with_very_deep_stack }
  if ARGV.include?('--forever')
    run_forever
  else
    run_benchmark
  end
end
