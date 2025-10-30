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

    return if Datadog::Core::DDSketch.supported?

    # Skip if DDSketch is not available (e.g., in Nix environments where libdatadog isn't built)
    testcase.skip("Data Streams Monitoring is not available: DDSketch is not supported")
  end
end

RSpec.configure do |config|
  config.include DataStreamsHelpers
end
