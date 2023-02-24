# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'pry'
require_relative 'dogstatsd_reporter'

# This benchmark measures the performance of the main stack sampling loop of the profiler

class ProfilerSampleLoopBenchmark
  class MockProfilerTransport
    def export(_flush)
    end
  end

  def create_profiler
    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.exporter.transport = MockProfilerTransport.new
      c.tracing.transport_options = proc { |t| t.adapter :test }
    end

    # Stop background threads
    Datadog.shutdown!

    # Call collection directly
    @stack_collector = Datadog.send(:components).profiler.collectors.first
    @recorder = @stack_collector.recorder
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
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 70, warmup: 2}
      x.config(**benchmark_time, suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_sample_loop'))

      x.report("stack collector #{ENV['CONFIG']}") do
        @stack_collector.collect_and_wait
      end

      x.save! 'profiler-sample-loop-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize
  end

  def run_forever
    while true
      1000.times { @stack_collector.collect_and_wait }
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
