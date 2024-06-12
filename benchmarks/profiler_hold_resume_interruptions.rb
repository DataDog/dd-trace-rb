# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'datadog'
require 'pry'
require_relative 'dogstatsd_reporter'

# This benchmark measures the performance of the hold/resume interruptions used by the DirMonkeyPatches
class ProfilerHoldResumeInterruptions
  def create_profiler
    Datadog.configure do |c|
      c.profiling.enabled = true
    end
    Datadog::Profiling.wait_until_running
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
        suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'profiler_hold_resume_interruptions')
      )

      x.report("hold / resume") do
        Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_interruptions
        Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_interruptions
      end

      x.save! 'profiler_hold_resume_interruptions-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerHoldResumeInterruptions.new.instance_exec do
  create_profiler
  run_benchmark
end
