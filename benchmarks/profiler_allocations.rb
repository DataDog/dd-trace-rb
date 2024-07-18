# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'datadog'
require 'pry'
require_relative 'dogstatsd_reporter'

# This benchmark measures the performance of GC profiling

class ProfilerGcBenchmark
  def run_benchmark
    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.allocation_enabled = true
      c.profiling.advanced.gc_enabled = false
    end
    Datadog::Profiling.wait_until_running

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
        suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_gc_integration_allocations')
      )

      x.report("Allocations (profiling enabled) #{ENV['VARIANT']}", 'Object.new')

      x.save! 'profiler-gc-integration-allocations-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerGcBenchmark.new.instance_exec do
  run_benchmark
end
