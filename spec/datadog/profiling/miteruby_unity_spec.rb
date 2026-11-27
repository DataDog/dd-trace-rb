require "datadog/profiling/spec_helper"
require "open3"

RSpec.describe "miteruby_unity.o" do
  before { skip_if_profiling_not_supported }

  # Allow-list of functions that get exposed outside of miteruby for other parts of the compiler to call.
  # If this and you want something new to be called from the outside, add it here.
  # If this fails and you didn't expect something to be called from the outside, add `static` or `MITERUBY_INTERNAL` to it.
  it "defines only the global symbols used by the rest of the profiling extension" do
    extension = "datadog_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
    object = File.expand_path("../../../tmp/#{RUBY_PLATFORM}/#{extension}/#{RUBY_VERSION}/miteruby_unity.o", __dir__)
    defined_only = PlatformHelpers.mac? ? "-U" : "--defined-only"
    output, error, status = Open3.capture3("nm", "-g", "-P", defined_only, object)
    expect(status).to be_success, error

    symbols = output.lines.map { |line| line.split.first }
    symbols.map! { |name| name.delete_prefix("_") } if PlatformHelpers.mac?
    expect(symbols).to match_array(%w[
      miteruby_consumer_consume_loop
      miteruby_consumer_init
      miteruby_consumer_prepare_serialize
      miteruby_consumer_reset
      miteruby_consumer_stats
      miteruby_init_can_overflow
      miteruby_raw_events_queue_destroy
      miteruby_raw_events_queue_init
      miteruby_raw_events_queue_read
      miteruby_raw_events_queue_wake_consumer
      miteruby_sample_event_publish_mask
      miteruby_sample_event_publish_sighandler
      miteruby_sample_event_publish_testing
      miteruby_serializer_init
    ])
  end
end
