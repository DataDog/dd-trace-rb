# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# This benchmark measures the performance of GC profiling

class ProfilerGcBenchmark
  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: true,
      alloc_samples_enabled: false,
      heap_samples_enabled: false,
      heap_size_enabled: false,
      heap_sample_every: 1,
      timeline_enabled: true,
    )
    @collector = Datadog::Profiling::Collectors::ThreadContext.new(
      recorder: @recorder, max_frames: 400, tracer: nil, endpoint_collection_enabled: false, timeline_enabled: true
    )

    # We take a dummy sample so that the context for the main thread is created, as otherwise the GC profiling methods do
    # not create it (because we don't want to do memory allocations in the middle of GC)
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, Thread.current)
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      # The idea of this benchmark is to test the overall cost of the Ruby VM calling these methods on every GC.
      # We're going as fast as possible (not realistic), but this should give us an upper bound for expected performance.
      x.report('profiler gc') do
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_start(@collector)
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_finish(@collector)
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample_after_gc(@collector, false)
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      # We cap the number of minor GC samples to not happen more often than TIME_BETWEEN_GC_EVENTS_NS (10)
      minor_gc_per_second_upper_bound = 100
      # ...but every major GC triggers a flush. Here we consider what would happen if we had 1000 major GCs per second
      pessimistic_number_of_gcs_per_second = minor_gc_per_second_upper_bound * 10
      estimated_gc_per_minute = pessimistic_number_of_gcs_per_second * 60

      x.report("estimated profiler gc per minute (sample #{estimated_gc_per_minute} times + serialize result)") do
        estimated_gc_per_minute.times do
          Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_start(@collector)
          Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_finish(@collector)
          Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample_after_gc(@collector, false)
        end

        @recorder.serialize
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('Major GC runs (profiling disabled)', 'GC.start')

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.allocation_enabled = false
      c.profiling.advanced.gc_enabled = true
    end
    Datadog::Profiling.wait_until_running

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('Major GC runs (profiling enabled)', 'GC.start')

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Datadog.configure { |c| c.profiling.enabled = false }

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('Allocations (profiling disabled)', 'Object.new')

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.allocation_enabled = false
      c.profiling.advanced.gc_enabled = true
    end
    Datadog::Profiling.wait_until_running

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('Allocations (profiling enabled)', 'Object.new')

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    @recorder.serialize
  end
end

puts "Current pid is #{Process.pid}"

ProfilerGcBenchmark.new.instance_exec do
  create_profiler
  run_benchmark
end
