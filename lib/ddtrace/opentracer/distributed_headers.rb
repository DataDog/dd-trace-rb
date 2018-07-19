require 'ddtrace/span'
require 'ddtrace/ext/distributed'

module Datadog
  module OpenTracer
    # DistributedHeaders provides easy access and validation to headers
    class DistributedHeaders
      include Datadog::Ext::DistributedTracing

      def initialize(carrier)
        @carrier = carrier
      end

      def valid?
        # Sampling priority is optional.
        !trace_id.nil? && !parent_id.nil?
      end

      def trace_id
        value = @carrier[HTTP_HEADER_TRACE_ID].to_i
        return if value <= 0 || value >= Datadog::Span::MAX_ID
        value
      end

      def parent_id
        value = @carrier[HTTP_HEADER_PARENT_ID].to_i
        return if value <= 0 || value >= Datadog::Span::MAX_ID
        value
      end

      def sampling_priority
        hdr = @carrier[HTTP_HEADER_SAMPLING_PRIORITY]
        # It's important to make a difference between no header,
        # and a header defined to zero.
        return unless hdr
        value = hdr.to_i
        return if value < 0
        value
      end
    end
  end
end
