# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

if RUBY_VERSION < '3.2'
  if VALIDATE_BENCHMARK_MODE
    # To simplify things, we allow this benchmark to be run in VALIDATE_BENCHMARK_MODE even though it's a no-op
    $stderr.puts "Skipping benchmark because it requires Ruby 3.2 or newer"
    return
  else
    raise 'This benchmark requires Ruby 3.2 or newer'
  end
end

# This benchmark measures the performance of the main stack sampling loop of the profiler

class ProfilerSampleGvlBenchmark
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def initialize
    create_profiler
    @target_thread = thread_with_very_deep_stack

    # Sample once to trigger thread context creation for all threads (including @target_thread)
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
  end

  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: true,
      alloc_samples_enabled: false,
      heap_samples_enabled: false,
      heap_size_enabled: false,
      heap_sample_every: 1,
      timeline_enabled: true,
    )
    @collector = Datadog::Profiling::Collectors::ThreadContext.for_testing(
      recorder: @recorder,
      waiting_for_gvl_threshold_ns: 0,
      timeline_enabled: true,
    )
  end

  def thread_with_very_deep_stack(depth: 200)
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
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 20, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report("gvl benchmark samples") do
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gvl_waiting(@target_thread)
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gvl_running(@target_thread)
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample_after_gvl_running(@collector, @target_thread)
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize!
  end
end

puts "Current pid is #{Process.pid}"

ProfilerSampleGvlBenchmark.new.instance_exec do
  run_benchmark
end
