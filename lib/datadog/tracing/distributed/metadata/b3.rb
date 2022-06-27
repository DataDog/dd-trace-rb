# typed: true

require 'datadog/tracing/distributed/helpers'
require 'datadog/tracing/distributed/metadata_parser'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/trace_digest'

module Datadog
  module Tracing
    module Distributed
      module Metadata
        # B3 provides helpers to inject or extract headers for B3 style headers
        module B3
          include Distributed::Headers::Ext

          def self.inject!(digest, metadata)
            return if digest.nil?

            # DEV: We need these to be hex encoded
            metadata[B3_METADATA_TRACE_ID] = digest.trace_id.to_s(16)
            metadata[B3_METADATA_SPAN_ID] = digest.span_id.to_s(16)

            if digest.trace_sampling_priority
              sampling_priority = Helpers.clamp_sampling_priority(
                digest.trace_sampling_priority
              )
              metadata[B3_HEADER_SAMPLED] = sampling_priority.to_s
            end

            metadata
          end

          def self.extract(metadata)
            # Extract values from gRPC metadata
            # DEV: B3 doesn't have "origin"
            metadata = MetadataParser.new(metadata)
            trace_id = metadata.id(B3_METADATA_TRACE_ID, 16)
            span_id = metadata.id(B3_METADATA_SPAN_ID, 16)
            # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
            sampling_priority = metadata.number(B3_METADATA_SAMPLED)

            # Return early if this propagation is not valid
            return unless trace_id && span_id

            TraceDigest.new(
              trace_id: trace_id,
              span_id: span_id,
              trace_sampling_priority: sampling_priority
            )
          end
        end
      end
    end
  end
end
