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
      # Sampling priority is optional.
      trace_id && parent_id
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
      hdr = header(HTTP_HEADER_SAMPLING_PRIORITY)
      # It's important to make a difference between no header,
      # and a header defined to zero.
      return unless hdr
      value = hdr.to_i
      return if value < 0
      value
    end

    private

    def header(name)
      rack_header = "http-#{name}".upcase!.tr('-', '_')

      @env[rack_header]
    end
  end
end
