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
        id HTTP_HEADER_TRACE_ID
      end

      def parent_id
        id HTTP_HEADER_PARENT_ID
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

      def origin
        hdr = @carrier[HTTP_HEADER_ORIGIN]
        # Only return the value if it is not an empty string
        hdr if hdr != ''
      end

      private

      def id(header)
        value = @carrier[header].to_i
        return if value.zero? || value >= Datadog::Span::EXTERNAL_MAX_ID
        value < 0 ? value + 0x1_0000_0000_0000_0000 : value
      end
    end
  end
end
