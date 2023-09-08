require 'ddtrace'
require 'pry'
require 'datadog/profiling/pprof/pprof_pb'

class DeepStackSimulator
  def self.thread_with_stack_depth(depth)
    ready_queue = Queue.new

    # In spec_helper.rb we have a DatadogThreadDebugger which is used to help us debug specs that leak threads.
    # Since in this helper we want to have precise control over how many frames are on the stack of a given thread,
    # we need to take into account that the DatadogThreadDebugger adds one more frame to the stack.
    first_method =
      defined?(DatadogThreadDebugger) && Thread.include?(DatadogThreadDebugger) ? :deep_stack_2 : :deep_stack_1

    thread = Thread.new(&DeepStackSimulator.new(target_depth: depth, ready_queue: ready_queue).method(first_method))
    thread.name = "Deep stack #{depth}" if thread.respond_to?(:name=)
    ready_queue.pop

    thread
  end

  def initialize(target_depth:, ready_queue:)
    @target_depth = target_depth
    @ready_queue = ready_queue

    define_methods(target_depth)
  end

  # We use this weird approach to both get an exact depth, as well as have a method with a unique name for
  # each depth
  def define_methods(target_depth)
    (1..target_depth).each do |depth|
      next if respond_to?(:"deep_stack_#{depth}")

      # rubocop:disable Security/Eval
      eval(
        %(
        def deep_stack_#{depth}                               # def deep_stack_1
          if Thread.current.backtrace.size < @target_depth    #   if Thread.current.backtrace.size < @target_depth
            deep_stack_#{depth + 1}                           #     deep_stack_2
          else                                                #   else
            @ready_queue << :read_ready_pipe                  #     @ready_queue << :read_ready_pipe
            sleep                                             #     sleep
          end                                                 #   end
        end                                                   # end
      ),
        binding,
        __FILE__,
        __LINE__ - 12
      )
      # rubocop:enable Security/Eval
    end
  end
end

class RubyOverheadExperiment
  # This is needed because we're directly invoking the collector through a testing interface; in normal
  # use a profiler thread is automatically used.
  PROFILER_OVERHEAD_STACK_THREAD = Thread.new { sleep }

  def create_profiler(timeline_enabled:)
    @recorder = Datadog::Profiling::StackRecorder.new(cpu_time_enabled: true, alloc_samples_enabled: true)
    @collector = Datadog::Profiling::Collectors::ThreadContext.new(
      recorder: @recorder, max_frames: 400, tracer: nil, endpoint_collection_enabled: false, timeline_enabled: timeline_enabled
    )
  end

  def simulate(**config)
    threads = config.fetch(:threads)
    depth = config.fetch(:depth)
    seconds = config.fetch(:seconds)
    timeline_enabled = config.fetch(:timeline_enabled)

    # config => {threads:, depth:, seconds:, timeline_enabled:}

    puts "config: #{config}"
    create_profiler(timeline_enabled: timeline_enabled)
    threads.times { DeepStackSimulator.thread_with_stack_depth(depth) }

    samples_per_second = 100

    seconds.times do
      samples_per_second.times do
        Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
      end
    end

    puts "Before serialization, process rss usage is #{current_rss}k"

    start, _, pprof = @recorder.serialize

    puts "After serialization, process rss usage is #{current_rss}k"

    puts "Size of compressed serialized pprof: #{pprof.size / 1024}k"

    File.write("ruby-overhead-experiment-#{threads}-#{depth}-#{seconds}-timeline-#{timeline_enabled}.pprof", pprof)

    # run_analysis(pprof)

    pprof = nil
    10.times { @recorder.serialize }

    @recorder = nil
    @collector = nil

    10.times { GC.start; GC.compact }

    puts "After shrinking, process rss usage is #{current_rss}k"

    # sleep
  end

  def current_rss
    Integer(`ps h -q #{Process.pid} -o rss`)
  end

  def run_analysis(pprof)
    decoded_profile = ::Perftools::Profiles::Profile.decode(pprof)

    puts "Pprof had #{decoded_profile.sample.size} samples"
  end
end

RubyOverheadExperiment.new.simulate(threads: 16, depth: 50, seconds: 60, timeline_enabled: ENV['TIMELINE'] == 'true')
