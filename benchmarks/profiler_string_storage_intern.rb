# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# This benchmark measures the performance of string storage intern/intern_all APIs

class ProfilerStringStorageIntern
  def initialize
    @recorder = Datadog::Profiling::StackRecorder.for_testing(heap_samples_enabled: true)
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('intern 1000 strings') do
        Datadog::Profiling::StackRecorder::Testing._native_benchmark_intern(@recorder, "hello, world!", 1000, false)
      end

      x.report('intern_all 1000 strings') do
        Datadog::Profiling::StackRecorder::Testing._native_benchmark_intern(@recorder, "hello, world!", 1000, true)
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerStringStorageIntern.new.instance_exec do
  run_benchmark
end
