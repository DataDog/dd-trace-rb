require_relative 'lib/boot'

# This benchmark measures the performance of the main stack sampling loop of the profiler
benchmarks(__FILE__) do
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler
    @recorder = Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: true,
      alloc_samples_enabled: false,
      heap_samples_enabled: false,
      heap_size_enabled: false,
      heap_sample_every: 1,
      timeline_enabled: false,
    )
    @collector = Datadog::Profiling::Collectors::ThreadContext.new(
      recorder: @recorder, max_frames: 400, tracer: nil, endpoint_collection_enabled: false, timeline_enabled: false
    )
  end

  before do
    create_profiler
    4.times { thread_with_very_deep_stack }
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

  benchmark("stack collector #{ENV['CONFIG']}") do
    Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
  end

  after do
    @recorder.serialize
  end

  def run_forever
    while true
      1000.times do
        run_benchmarks
      end
      run_after
      print '.'
    end
  end
end
