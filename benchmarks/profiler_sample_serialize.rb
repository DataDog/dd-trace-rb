require_relative 'lib/boot'

# This benchmark measures the performance of sampling + serializing profiles. It enables us to evaluate changes to
# the profiler and/or libdatadog that may impact both individual samples, as well as samples over time (e.g. timeline).
Benchmarker.define do

  before do
    require 'libdatadog'

    puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"
  end

  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler
    timeline_enabled = ENV['TIMELINE'] == 'true'
    @recorder = Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: true,
      alloc_samples_enabled: false,
      heap_samples_enabled: false,
      heap_size_enabled: false,
      heap_sample_every: 1,
      timeline_enabled: timeline_enabled,
    )
    @collector = Datadog::Profiling::Collectors::ThreadContext.new(
      recorder: @recorder, max_frames: 400, tracer: nil, endpoint_collection_enabled: false, timeline_enabled: timeline_enabled
    )
  end

  before do
    create_profiler
    10.times { Thread.new { sleep } }
  end

  benchmark("sample #{ENV['CONFIG']} timeline=#{ENV['TIMELINE'] == 'true'}") do
    samples_per_second = 100
    simulate_seconds = 60

    (samples_per_second * simulate_seconds).times do
      Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
    end

    @recorder.serialize
    nil
  end

  after do
    @recorder.serialize
  end

  def run_forever
    while true
      1000.times do
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
      end
      @recorder.serialize
      print '.'
    end
  end
end
