require_relative 'lib/boot'

# This benchmark measures the performance of sampling + serializing memory profiles. It enables us to evaluate changes to
# the profiler and/or libdatadog that may impact both individual samples, as well as samples over time.
Benchmarker.define(__FILE__) do
  before do
    require 'libdatadog'

    puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"
  end

  METRIC_VALUES = { 'cpu-time' => 0, 'cpu-samples' => 0, 'wall-time' => 0, 'alloc-samples' => 1, 'timeline' => 0 }.freeze
  OBJECT_CLASS = 'object'.freeze

  def sample_object(recorder, depth = 0)
    if depth <= 0
      obj = Object.new
      Datadog::Profiling::StackRecorder::Testing._native_track_object(
        recorder,
        obj,
        1,
        OBJECT_CLASS,
      )
      Datadog::Profiling::Collectors::Stack::Testing._native_sample(
        Thread.current,
        recorder,
        METRIC_VALUES,
        [],
        [],
        400,
        false
      )
      obj
    else
      sample_object(recorder, depth - 1)
    end
  end

  before do
    @heap_samples_enabled = ENV['HEAP_SAMPLES'] == 'true'
    @heap_size_enabled = ENV['HEAP_SIZE'] == 'true'
    @heap_sample_every = (ENV['HEAP_SAMPLE_EVERY'] || '1').to_i
    @retain_every = (ENV['RETAIN_EVERY'] || '10').to_i
    @skip_end_gc = ENV['SKIP_END_GC'] == 'true'
    @recorder_factory = proc {
      Datadog::Profiling::StackRecorder.new(
        cpu_time_enabled: false,
        alloc_samples_enabled: true,
        heap_samples_enabled: @heap_samples_enabled,
        heap_size_enabled: @heap_size_enabled,
        heap_sample_every: @heap_sample_every,
        timeline_enabled: false,
      )
    }
  end

  benchmark("sample+serialize #{ENV['CONFIG']} retain_every=#{@retain_every} heap_samples=#{@heap_samples_enabled} heap_size=#{@heap_size_enabled} heap_sample_every=#{@heap_sample_every} skip_end_gc=#{@skip_end_gc}", time: 30) do
    recorder = @recorder_factory.call
    samples_per_second = 100
    simulate_seconds = 60
    retained_objs = []

    (samples_per_second * simulate_seconds).times do |i|
      obj = sample_object(recorder, i % 400)
      retained_objs << obj if (i % @retain_every).zero?
    end

    GC.start unless @skip_end_gc

    recorder.serialize
  end

  def run_forever
    loop do
      recorder = @recorder_factory.call
      1000.times do |i|
        sample_object(recorder, i % 400)
      end
      recorder.serialize
      print '.'
    end
  end
end
