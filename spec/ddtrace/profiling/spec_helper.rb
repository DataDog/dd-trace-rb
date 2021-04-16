require 'ddtrace/profiling'

module ProfilingFeatureHelpers
  # Stubs Ruby classes before applying profiling patches.
  # This allows original, pristine classes to be restored after the test.
  RSpec.shared_context 'with profiling extensions' do
    before do
      stub_const('Thread', ::Thread.dup)
      stub_const('Process', ::Process.dup)
      stub_const('Kernel', ::Kernel.dup)

      require 'ddtrace/profiling/tasks/setup'
      Datadog::Profiling::Tasks::Setup::ACTIVATE_EXTENSIONS_ONLY_ONCE.send(:reset_ran_once_state_for_tests)
      Datadog::Profiling::Tasks::Setup.new.run
    end
  end

  # Helper for running profiling test in fork, e.g.:
  #
  #     it { profiling_in_fork { # Test assertions... } }
  #
  # This allows "real" profiling to be applied to Ruby classes without
  # lingering side effects (since patching occurs within a fork.)
  # Useful for profiling tests involving the main Thread, which cannot
  # be unpatched after applying profiling extensions.
  def with_profiling_extensions_in_fork(fork_expectations: nil)
    # Apply extensions in a fork so we don't modify the original Thread class
    expect_in_fork(fork_expectations: fork_expectations) do
      require 'ddtrace/profiling/tasks/setup'
      Datadog::Profiling::Tasks::Setup::ACTIVATE_EXTENSIONS_ONLY_ONCE.send(:reset_ran_once_state_for_tests)
      Datadog::Profiling::Tasks::Setup.new.run
      yield
    end
  end
end

module ProfileHelpers
  def get_test_profiling_flush
    stack_one = Thread.current.backtrace_locations.first(3)
    stack_two = Thread.current.backtrace_locations.first(3)

    stack_samples = [
      build_stack_sample(stack_one, 100, 0, 0, 100, 100),
      build_stack_sample(stack_two, 100, 0, 0, 200, 200),
      build_stack_sample(stack_one, 101, 0, 0, 400, 400),
      build_stack_sample(stack_two, 101, 0, 0, 800, 800),
      build_stack_sample(stack_two, 101, 0, 0, 1600, 1600)
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

  def build_stack_sample(
    locations = nil,
    thread_id = nil,
    trace_id = nil,
    span_id = nil,
    cpu_time_ns = nil,
    wall_time_ns = nil
  )
    locations ||= Thread.current.backtrace_locations

    Datadog::Profiling::Events::StackSample.new(
      nil,
      locations,
      locations.length,
      thread_id || rand(1e9),
      trace_id || rand(1e9),
      span_id || rand(1e9),
      cpu_time_ns || rand(1e9),
      wall_time_ns || rand(1e9)
    )
  end
end

RSpec.configure do |config|
  config.include ProfileHelpers
  config.include ProfilingFeatureHelpers
end
