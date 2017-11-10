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

    def self.inject!(span, env)
      headers = { HTTP_HEADER_TRACE_ID => span.trace_id.to_s,
                  HTTP_HEADER_PARENT_ID => span.span_id.to_s }
      if span.sampling_priority
        headers[HTTP_HEADER_SAMPLING_PRIORITY] = span.sampling_priority.to_s
      end
      env.merge! headers
      env.delete(HTTP_HEADER_SAMPLING_PRIORITY) unless span.sampling_priority
    end

    def self.extract(env)
      headers = DistributedHeaders.new(env)
      return Datadog::Context.new unless headers.valid?
      Datadog::Context.new(trace_id: headers.trace_id,
                           span_id: headers.parent_id,
                           sampling_priority: headers.sampling_priority)
    end

    private

    def header(name)
      rack_header = "http-#{name}".upcase!.tr('-', '_')

      @env[rack_header]
    end
  end
end
