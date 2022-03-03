# typed: true
require 'datadog/profiling'

module ProfileHelpers
  include Kernel

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

  def skip_if_profiling_not_supported(testcase)
    testcase.skip('Profiling is not supported on JRuby') if PlatformHelpers.jruby?
    testcase.skip('Profiling is not supported on TruffleRuby') if PlatformHelpers.truffleruby?

    # Profiling is not officially supported on macOS due to missing libddprof binaries,
    # but it's still useful to allow it to be enabled for development.
    if PlatformHelpers.mac? && ENV['DD_PROFILING_MACOS_TESTING'] != 'true'
      testcase.skip(
        'Profiling is not supported on macOS. If you still want to run these specs, you can use ' \
        'DD_PROFILING_MACOS_TESTING=true to override this check.'
      )
    end

    return if Datadog::Profiling.supported?

    # Ensure profiling was loaded correctly
    raise "Profiling does not seem to be available: #{Datadog::Profiling.unsupported_reason}. " \
      'Try running `bundle exec rake compile` before running this test.'
  end
end

RSpec.configure do |config|
  config.include ProfileHelpers
end
