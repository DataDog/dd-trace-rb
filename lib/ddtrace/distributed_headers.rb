require 'ddtrace/span'
require 'ddtrace/ext/distributed'

module Datadog
  # DistributedHeaders provides easy access and validation to headers
  class DistributedHeaders
    include Ext::DistributedTracing

    def initialize(env)
      @env = env
    end

    def valid?
      trace_id && parent_id && sampling_priority
    end

    def trace_id
      value = header(HTTP_HEADER_TRACE_ID).to_i
      return if value <= 0 || value >= Span::MAX_ID
      value
    end

    def parent_id
      value = header(HTTP_HEADER_PARENT_ID).to_i
      return if value <= 0 || value >= Span::MAX_ID
      value
    end

    def sampling_priority
      value = header(HTTP_HEADER_SAMPLING_PRIORITY).to_f
      return unless SAMPLING_PRIORITY_RANGE.include?(value)
      value
    end

    private

    def header(name)
      rack_header = "http-#{name}".upcase!.tr('-', '_')

      @env[rack_header]
    end
  end
end
