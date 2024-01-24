require 'ddtrace'
require 'pry'
require 'libdatadog'

puts "Libdatadog from: #{Libdatadog.pkgconfig_folder}"

class RubyOverheadExperiment
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler(timeline_enabled:)
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

  def workload(steps_per_sample:, loop_times:, profile:, sync_queue:)
    sync_queue.pop

    count = 0
    while count < loop_times
      steps = 0

      while steps < steps_per_sample
        SecureRandom.bytes(rand(10000))
        Thread.pass
        steps +=1
      end

      Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD) if profile

      count += 1
    end
  end


  def simulate(**config)
    threads = config.fetch(:threads)
    seconds = config.fetch(:seconds)
    timeline_enabled = config.fetch(:timeline_enabled)
    profiler_enabled = config.fetch(:profiler_enabled)

    puts "config: #{config}"
    create_profiler(timeline_enabled: timeline_enabled)

    puts "At benchmark start, process rss usage is #{current_rss}k"

    10.times do
      start_time = Time.now

      sync_queue = Queue.new

      threads = seconds.times.map do
        Thread.new { workload(steps_per_sample: 10, loop_times: seconds, profile: profiler_enabled, sync_queue: sync_queue) }
      end

      seconds.times { sync_queue << true }

      threads.each(&:join)

      @recorder.serialize

      3.times { GC.start }

      puts "Ran through every step in #{(Time.now - start_time).to_f.round(2)}s, process rss usage is #{current_rss}k"
    end
  end

  def current_rss
    Integer(`ps h -q #{Process.pid} -o rss`)
  end
end

RubyOverheadExperiment.new.simulate(threads: 100, seconds: 60, timeline_enabled: ENV['TIMELINE'] == 'true', profiler_enabled: ENV['PROFILER'] == 'true')
