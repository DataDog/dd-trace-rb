# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# This benchmark measures the performance of the main stack sampling loop of the profiler

class ProfilerSampleLoopBenchmark
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.for_testing
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

  def thread_with_very_deep_stack_and_native_frames(depth: 500)
    deep_stack = proc do |n|
      catch do
        if n > 0
          deep_stack.call(n - 1)
        else
          sleep
        end
      end
    end

    Thread.new { deep_stack.call(depth) }.tap { |t| t.name = "Deep stack #{depth}" }
  end

  def run_benchmark(mode: :ruby)
    threads = Array.new(4) { mode == :ruby ? thread_with_very_deep_stack : thread_with_very_deep_stack_and_native_frames }
    collector = Datadog::Profiling::Collectors::ThreadContext.for_testing(recorder: @recorder)

    if mode == :native
      unless Datadog::Profiling::Collectors::Stack._native_filenames_available?
        raise 'Native filenames are not available. This is expected on macOS, but not on Linux.'
      end

      collector_without_native_filenames = Datadog::Profiling::Collectors::ThreadContext.for_testing(
        recorder: @recorder,
        native_filenames_enabled: false
      )
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report("stack collector (#{mode} frames - native filenames enabled) #{ENV['CONFIG']}") do
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(
          collector,
          PROFILER_OVERHEAD_STACK_THREAD,
          false
        )
      end

      if mode == :native
        x.report("stack collector (#{mode} frames - native filenames disabled) #{ENV['CONFIG']}") do
          Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(
            collector_without_native_filenames,
            PROFILER_OVERHEAD_STACK_THREAD,
            false
          )
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    threads.map(&:kill).each(&:join)
    @recorder.serialize!
  end
end

puts "Current pid is #{Process.pid}"

ProfilerSampleLoopBenchmark.new.instance_exec do
  create_profiler
  run_benchmark(mode: :ruby)
  run_benchmark(mode: :native)
end
