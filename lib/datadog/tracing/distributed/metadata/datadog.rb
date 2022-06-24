require 'datadog/tracing/distributed/headers/ext'

module Datadog
  module Tracing
    module Distributed
      module Metadata
        class Datadog
          include Distributed::Headers::Ext

          def self.inject!(digest, metadata)
            return if digest.nil?

            metadata[GRPC_METADATA_TRACE_ID] = digest.trace_id.to_s
            metadata[GRPC_METADATA_PARENT_ID] = digest.span_id.to_s
            metadata[GRPC_METADATA_SAMPLING_PRIORITY] = digest.trace_sampling_priority.to_s if digest.trace_sampling_priority
            metadata[GRPC_METADATA_ORIGIN] = digest.trace_origin.to_s if digest.trace_origin

            metadata
          end

          def self.extract(metadata)
            carrier = Carrier.new(metadata)

            return nil unless carrier.valid?

            TraceDigest.new(
              span_id: carrier.parent_id,
              trace_id: carrier.trace_id,
              trace_origin: carrier.origin,
              trace_sampling_priority: carrier.sampling_priority
            )
          end

          class Carrier
            include Distributed::Headers::Ext

            def initialize(metadata = {})
              @metadata = metadata || {}
            end

            def valid?
              (trace_id && parent_id) || (origin && trace_id)
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
end
