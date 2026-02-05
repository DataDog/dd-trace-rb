# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'os'

# This benchmark measures the performance of the main stack sampling loop of the profiler

VARYING_DEPTH_DEFAULT = 2900

class ProfilerSampleLoopBenchmark
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.for_testing
  end

  def thread_with_very_deep_stack(depth: 450)
    deep_stack = proc do
      if caller.size <= depth
        deep_stack.call
      else
        sleep
      end
    end

    Thread.new { deep_stack.call }.tap { |t| t.name = "Deep stack #{depth}" }
  end

  def thread_with_very_deep_stack_and_native_frames(depth: 450)
    deep_stack = proc do
      catch do
        if caller.size <= depth
          deep_stack.call
        else
          sleep
        end
      end
    end

    Thread.new { deep_stack.call }.tap { |t| t.name = "Deep stack #{depth}" }
  end

  def go_to_depth_and_run(depth:, &block)
    current_depth = caller.size
    return yield if current_depth > depth

    # rubocop:disable Lint/DuplicateBranch
    # Simulate "some" complexity in the method bytecode
    case current_depth % 10
    when 0
      go_to_depth_and_run(depth: depth, &block)
    when 1
      go_to_depth_and_run(depth: depth, &block)
    when 2
      go_to_depth_and_run(depth: depth, &block)
    when 3
      go_to_depth_and_run(depth: depth, &block)
    when 4
      go_to_depth_and_run(depth: depth, &block)
    when 5
      go_to_depth_and_run(depth: depth, &block)
    when 6
      go_to_depth_and_run(depth: depth, &block)
    when 7
      go_to_depth_and_run(depth: depth, &block)
    when 8
      go_to_depth_and_run(depth: depth, &block)
    when 9
      go_to_depth_and_run(depth: depth, &block)
    end
    # rubocop:enable Lint/DuplicateBranch
  end

  def run_benchmark(mode: :ruby)
    threads = Array.new(4) { (mode == :ruby) ? thread_with_very_deep_stack : thread_with_very_deep_stack_and_native_frames }
    collector = Datadog::Profiling::Collectors::ThreadContext.for_testing(recorder: @recorder)

    if mode == :native
      unless Datadog::Profiling::Collectors::Stack._native_filenames_available?
        if OS.linux?
          raise 'Native filenames are not available. This is not expected on Linux!'
        else
          puts 'Skipping benchmarking native_frames, not supported outside of Linux'
          return
        end
      end

      Datadog::Profiling::Collectors::ThreadContext.for_testing(
        recorder: @recorder,
        native_filenames_enabled: false
      )
      collector_without_native_filenames = collector
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report("stack collector (#{mode} frames - native filenames enabled) #{ENV["CONFIG"]}") { sample(collector) }

      if mode == :native
        x.report("stack collector (#{mode} frames - native filenames disabled) #{ENV["CONFIG"]}") do
          sample(collector_without_native_filenames)
        end
      end

      x.save! "#{File.basename(__FILE__)}-#{mode}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    threads.map(&:kill).each(&:join)
    @recorder.serialize!
  end

  def run_varying_depth_benchmark
    collector = Datadog::Profiling::Collectors::ThreadContext.for_testing(recorder: @recorder, max_frames: 3000)

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      # This benchmark checks the performance of samples when the stack keeps changing
      x.report("stack collector (varying depth) #{ENV["CONFIG"]}") do
        sample(collector)
        add_extra_frame_and_sample(collector) # This makes the stack change
      end

      x.save! "#{File.basename(__FILE__)}-varying-depth-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize!
  end

  def sample(collector)
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(
      collector,
      PROFILER_OVERHEAD_STACK_THREAD,
      false
    )
  end

  def add_extra_frame_and_sample(collector)
    sample(collector)
  end
end

puts "Current pid is #{Process.pid}"

ProfilerSampleLoopBenchmark.new.instance_exec do
  create_profiler
  run_benchmark(mode: :ruby)
  run_benchmark(mode: :native)
  go_to_depth_and_run(depth: VALIDATE_BENCHMARK_MODE ? 10 : VARYING_DEPTH_DEFAULT) { run_varying_depth_benchmark }
end
