# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# This benchmark measures the performance of string storage-related APIs

class ProfilerStringStorageIntern
  def initialize
    @recorder = Datadog::Profiling::StackRecorder.for_testing(heap_samples_enabled: true)
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )
      x.report('intern_all 1000 repeated strings') do
        Datadog::Profiling::StackRecorder::Testing._native_benchmark_intern(@recorder, "hello, world!", 1000, true)
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-1-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('intern mixed existing and new') do
        recorder = Datadog::Profiling::StackRecorder.for_testing(heap_samples_enabled: true)

        strings_to_intern = 100_000
        existing_strings = (strings_to_intern * 0.9).to_i
        new_strings = strings_to_intern - existing_strings

        new_strings.times do |i|
          Datadog::Profiling::StackRecorder::Testing._native_benchmark_intern(recorder, ("%010d" % i), 1, false)
        end

        existing_strings.times do |i|
          Datadog::Profiling::StackRecorder::Testing._native_benchmark_intern(recorder, "hello, world!", 1, false)
        end
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-2-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerStringStorageIntern.new.instance_exec do
  run_benchmark
end
