# typed: false
require 'ddtrace/profiling'

module ProfileHelpers
  include Kernel

  def get_test_profiling_flush
    stack_one = Array(Thread.current.backtrace_locations).first(3)
    stack_two = Array(Thread.current.backtrace_locations).first(3)

    stack_samples = [
      build_stack_sample(
        locations: stack_one, thread_id: 100, root_span_id: 0, span_id: 0, cpu_time_ns: 100, wall_time_ns: 100
      ),
      build_stack_sample(
        locations: stack_two, thread_id: 100, root_span_id: 0, span_id: 0, cpu_time_ns: 200, wall_time_ns: 200
      ),
      build_stack_sample(
        locations: stack_one, thread_id: 101, root_span_id: 0, span_id: 0, cpu_time_ns: 400, wall_time_ns: 400
      ),
      build_stack_sample(
        locations: stack_two, thread_id: 101, root_span_id: 0, span_id: 0, cpu_time_ns: 800, wall_time_ns: 800
      ),
      build_stack_sample(
        locations: stack_two, thread_id: 101, root_span_id: 0, span_id: 0, cpu_time_ns: 1600, wall_time_ns: 1600
      )
    ]

    start = Time.now.utc
    finish = start + 10
    event_groups = [Datadog::Profiling::EventGroup.new(Datadog::Profiling::Events::StackSample, stack_samples)]

    Datadog::Profiling::Flush.new(
      start: start,
      finish: finish,
      event_groups: event_groups,
      event_count: stack_samples.length,
    )
  end

  def build_stack_sample(
    locations: nil,
    thread_id: nil,
    root_span_id: nil,
    span_id: nil,
    trace_resource: nil,
    cpu_time_ns: nil,
    wall_time_ns: nil
  )
    locations ||= Thread.current.backtrace_locations

    Datadog::Profiling::Events::StackSample.new(
      nil,
      locations.map do |location|
        Datadog::Profiling::BacktraceLocation.new(location.base_label, location.lineno, location.path)
      end,
      locations.length,
      thread_id || rand(1e9),
      root_span_id || rand(1e9),
      span_id || rand(1e9),
      trace_resource || "resource#{rand(1e9)}",
      cpu_time_ns || rand(1e9),
      wall_time_ns || rand(1e9)
    )
  end
end

RSpec.configure do |config|
  config.include ProfileHelpers
end
