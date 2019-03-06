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
      # Synthetics sends us `X-Datadog-Parent-Id: 0` which normally we would want
      # to filter out, but is ok in this context since there is no parent from Synthetics
      return true if origin == 'synthetics' && trace_id

      # Sampling priority and origin are optional.
      trace_id && parent_id
    end

    def trace_id
      id HTTP_HEADER_TRACE_ID
    end

    def parent_id
      id HTTP_HEADER_PARENT_ID
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

    def origin
      hdr = header(HTTP_HEADER_ORIGIN)
      # Only return the value if it is not an empty string
      hdr if hdr != ''
    end

    private

    def header(name)
      rack_header = "http-#{name}".upcase!.tr('-', '_')

      @env[rack_header]
    end

    def id(header)
      value = header(header).to_i
      return if value.zero? || value >= Span::MAX_ID
      value < 0 ? value + 0x1_0000_0000_0000_0000 : value
    end
  end
end
