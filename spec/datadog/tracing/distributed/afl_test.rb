lib = File.expand_path('lib')
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'datadog/tracing/distributed/datadog_tags_codec'
require 'afl'

AFL.with_logging_to_file('/tmp/afl-log') do
  AFL.init unless ENV['NO_AFL']
  AFL.with_exceptions_as_crashes do
    begin
      Datadog::Tracing::Distributed::DatadogTagsCodec.decode($stdin.readline)
    rescue Datadog::Tracing::Distributed::DatadogTagsCodec::DecodingError => _
    end
    exit!(0)
  end
end
