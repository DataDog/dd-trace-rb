# typed: true
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/trace_operation'

module Datadog
  module Tracing
    module Propagation
      # opentracing.io compliant methods for distributing trace headers
      # between two or more distributed services. Note this is very close
      # to the Propagation::HTTP; the key difference is the way gRPC handles
      # header information (called "metadata") as it operates over HTTP2
      module GRPC
        include Distributed::Headers::Ext

        def self.inject!(digest, metadata)
          return if digest.nil?

          digest = digest.to_digest if digest.is_a?(TraceOperation)

          metadata[GRPC_METADATA_TRACE_ID] = digest.trace_id.to_s
          metadata[GRPC_METADATA_PARENT_ID] = digest.span_id.to_s
          metadata[GRPC_METADATA_SAMPLING_PRIORITY] = digest.trace_sampling_priority.to_s if digest.trace_sampling_priority
          metadata[GRPC_METADATA_ORIGIN] = digest.trace_origin.to_s if digest.trace_origin
        end

        def self.extract(metadata)
          metadata = Carrier.new(metadata)
          return nil unless metadata.valid?

          TraceDigest.new(
            span_id: metadata.parent_id,
            trace_id: metadata.trace_id,
            trace_origin: metadata.origin,
            trace_sampling_priority: metadata.sampling_priority
          )
        end

        # opentracing.io compliant carrier object
        class Carrier
          include Distributed::Headers::Ext

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
  end
end
