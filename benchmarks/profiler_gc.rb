require_relative 'support/boot'

module ProfilerGcSetup
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

  def enable_profiling
    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.allocation_enabled = false
      c.profiling.advanced.gc_enabled = true
    end
    Datadog::Profiling.wait_until_running
  end

  def disable_profiling
    Datadog.configure { |c| c.profiling.enabled = false }
  end
end

# This benchmark measures the performance of GC profiling
Bechmarker.define do
  include ProfilerGcSetup

  before do
    create_profiler
  end

  # The idea of this benchmark is to test the overall cost of the Ruby VM calling these methods on every GC.
  # We're going as fast as possible (not realistic), but this should give us an upper bound for expected performance.
  benchmark 'profiler gc', time: 10 do
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_start(@collector)
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_finish(@collector)
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample_after_gc(@collector)
  end

  after do
    @recorder.serialize
  end
end

# This benchmark measures the performance of GC profiling
Bechmarker.define do
  include ProfilerGcSetup

  before do
    create_profiler

    # We cap the number of minor GC samples to not happen more often than TIME_BETWEEN_GC_EVENTS_NS (10)
    minor_gc_per_second_upper_bound = 100
    # ...but every major GC triggers a flush. Here we consider what would happen if we had 1000 major GCs per second
    pessimistic_number_of_gcs_per_second = minor_gc_per_second_upper_bound * 10
    @estimated_gc_per_minute = pessimistic_number_of_gcs_per_second * 60
  end

  benchmark "estimated profiler gc per minute (sample #{estimated_gc_per_minute} times + serialize result)" do
    @estimated_gc_per_minute.times do
      Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_start(@collector)
      Datadog::Profiling::Collectors::ThreadContext::Testing._native_on_gc_finish(@collector)
      Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample_after_gc(@collector)
    end
  end

  after do
    @recorder.serialize
  end
end

# This benchmark measures the performance of GC profiling
Bechmarker.define do
  include ProfilerGcSetup

  before do
    create_profiler
  end

  after do
    @recorder.serialize
  end

  benchmark 'Major GC runs (profiling disabled)' do
    GC.start
  end
end

# This benchmark measures the performance of GC profiling
Bechmarker.define do
  include ProfilerGcSetup

  before do
    create_profiler
    enable_profiling
  end

  after do
    disable_profiling
    @recorder.serialize
  end

  benchmark 'Major GC runs (profiling enabled)' do
    GC.start
  end
end

# This benchmark measures the performance of GC profiling
Bechmarker.define do
  include ProfilerGcSetup

  before do
    create_profiler
  end

  after do
    @recorder.serialize
  end

  benchmark 'Allocations (profiling disabled)' do
    Object.new
  end
end

# This benchmark measures the performance of GC profiling
Bechmarker.define do
  include ProfilerGcSetup

  before do
    create_profiler
    enable_profiling
  end

  after do
    disable_profiling
    @recorder.serialize
  end

  benchmark 'Allocations (profiling enabled)' do
    Object.new
  end
end
