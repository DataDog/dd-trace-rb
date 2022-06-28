# typed: true

require 'datadog/tracing/distributed/metadata/parser'
require 'datadog/tracing/distributed/helpers'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/trace_digest'

module Datadog
  module Tracing
    module Distributed
      module Metadata
        # B3Single provides helpers to inject or extract metadata for B3 single header style headers
        module B3Single
          include Distributed::Headers::Ext

          def self.inject!(digest, metadata)
            return if digest.nil?

            # Header format:
            #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
            # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
            # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

            # DEV: We need these to be hex encoded
            b3_header = "#{digest.trace_id.to_s(16)}-#{digest.span_id.to_s(16)}"

            if digest.trace_sampling_priority
              sampling_priority = Helpers.clamp_sampling_priority(
                digest.trace_sampling_priority
              )
              b3_header += "-#{sampling_priority}"
            end

            metadata[B3_METADATA_SINGLE] = b3_header

            metadata
          end

          def self.extract(metadata)
            # Metadata format:
            #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
            # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
            # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

            b3_single = Parser.new(metadata).metadata_for_key(B3_METADATA_SINGLE)
            return if b3_single.nil?

            parts = b3_single.split('-')
            trace_id = Helpers.value_to_id(parts[0], 16) unless parts.empty?
            span_id = Helpers.value_to_id(parts[1], 16) if parts.length > 1
            sampling_priority = Helpers.value_to_number(parts[2]) if parts.length > 2

            # Return early if this propagation is not valid
            return unless trace_id && span_id

            TraceDigest.new(
              span_id: span_id,
              trace_id: trace_id,
              trace_sampling_priority: sampling_priority
            )
          end
        end
      end
    end
  end
end
