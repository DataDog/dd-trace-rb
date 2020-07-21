require 'ddtrace/profiling'

module ProfilingFeatureHelpers
  RSpec.shared_context 'with profiling extensions' do
    around do |example|
      unmodified_class = ::Thread.dup

      # Setup profiling to add
      require 'ddtrace/profiling/tasks/setup'
      Datadog::Profiling::Tasks::Setup.new.run

      example.run
      Object.send(:remove_const, :Thread)
      Object.const_set('Thread', unmodified_class)
    end
  end
end

module ProfileHelpers
  def get_test_profiling_flush
    stack_one = Thread.current.backtrace_locations.first(3)
    stack_two = Thread.current.backtrace_locations.first(3)

    stack_samples = [
      build_stack_sample(stack_one, 100, 100, 100),
      build_stack_sample(stack_two, 100, 200, 200),
      build_stack_sample(stack_one, 101, 400, 400),
      build_stack_sample(stack_two, 101, 800, 800),
      build_stack_sample(stack_two, 101, 1600, 1600)
    ]

    start = Time.now.utc
    finish = start + 10
    event_groups = [Datadog::Profiling::EventGroup.new(Datadog::Profiling::Events::StackSample, stack_samples)]

    Datadog::Profiling::Flush.new(
      start,
      finish,
      event_groups,
      stack_samples.length
    )
  end

  def get_test_payload
    Datadog::Profiling::Encoding::Profile::Protobuf.encode(get_test_profiling_flush)
  end

  def build_stack_sample(locations = nil, thread_id = nil, cpu_time_ns = nil, wall_time_ns = nil)
    locations ||= Thread.current.backtrace_locations

    Datadog::Profiling::Events::StackSample.new(
      nil,
      locations,
      locations.length,
      thread_id || rand(1e9),
      cpu_time_ns || rand(1e9),
      wall_time_ns || rand(1e9)
    )
  end
end

RSpec.configure do |config|
  config.include ProfileHelpers
  config.include ProfilingFeatureHelpers
end
