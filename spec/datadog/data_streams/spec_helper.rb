# frozen_string_literal: true

module DataStreamsHelpers
  def skip_if_data_streams_not_supported(testcase)
    testcase.skip("Data Streams Monitoring is not supported on JRuby") if PlatformHelpers.jruby?
    testcase.skip("Data Streams Monitoring is not supported on TruffleRuby") if PlatformHelpers.truffleruby?

    # Data Streams Monitoring is not officially supported on macOS due to missing DDSketch binaries,
    # but it's still useful to allow it to be enabled for development.
    if PlatformHelpers.mac? && ENV["DD_DATA_STREAMS_MACOS_TESTING"] != "true"
      testcase.skip(
        "Data Streams Monitoring is not supported on macOS. If you still want to run these specs, you can use " \
        "DD_DATA_STREAMS_MACOS_TESTING=true to override this check."
      )
    end

    return if Datadog::Core.ddsketch_supported?

    # Ensure DDSketch was loaded correctly
    raise "DDSketch does not seem to be available: #{Datadog::Core::LIBDATADOG_API_FAILURE}. " \
      "Try running `bundle exec rake compile` before running this test."
  end
end

RSpec.configure do |config|
  config.include DataStreamsHelpers
end
