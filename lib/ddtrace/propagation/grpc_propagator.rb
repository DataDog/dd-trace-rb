require 'ddtrace/context'
require 'ddtrace/ext/distributed'

module Datadog
  # opentracing.io compliant methods for distributing trace context
  # between two or more distributed services. Note this is very close
  # to the HTTPPropagator; the key difference is the way gRPC handles
  # header information (called "metadata") as it operates over HTTP2
  module GRPCPropagator
    include Ext::DistributedTracing

    def self.inject!(context, metadata)
      metadata[GRPC_METADATA_TRACE_ID] = context.trace_id.to_s
      metadata[GRPC_METADATA_PARENT_ID] = context.span_id.to_s
      metadata[GRPC_METADATA_SAMPLING_PRIORITY] = context.sampling_priority.to_s if context.sampling_priority
      metadata[GRPC_METADATA_ORIGIN] = context.origin.to_s if context.origin
    end

    def self.extract(metadata)
      metadata = Carrier.new(metadata)
      return Datadog::Context.new unless metadata.valid?
      Datadog::Context.new(trace_id: metadata.trace_id,
                           span_id: metadata.parent_id,
                           sampling_priority: metadata.sampling_priority,
                           origin: metadata.origin)
    end

    # opentracing.io compliant carrier object
    class Carrier
      include Ext::DistributedTracing

      def initialize(metadata = {})
        @metadata = metadata || {}
      end

      def valid?
        trace_id && parent_id
      end

      def trace_id
        value = metadata_for_key(GRPC_METADATA_TRACE_ID).to_i
        value if (1..Span::EXTERNAL_MAX_ID).cover? value
      end

      def parent_id
        value = metadata_for_key(GRPC_METADATA_PARENT_ID).to_i
        value if (1..Span::EXTERNAL_MAX_ID).cover? value
      end

      def sampling_priority
        value = metadata_for_key(GRPC_METADATA_SAMPLING_PRIORITY)
        value && value.to_i
      end

      def origin
        value = metadata_for_key(GRPC_METADATA_ORIGIN)
        value if value != ''
      end

      private

      def metadata_for_key(key)
        # metadata values can be arrays (multiple headers with the same key)
        value = @metadata[key]
        if value.is_a?(Array)
          value.first
        else
          value
        end
      end
    end
  end
end
