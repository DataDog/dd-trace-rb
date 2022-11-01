# typed: true

require_relative 'helpers'
require_relative '../../trace_digest'

module Datadog
  module Tracing
    module Contrib
      module Distributed
        # B3Single provides helpers to inject or extract headers for B3 single header style headers
        # @see https://github.com/openzipkin/b3-propagation#single-header
        class B3Single
          def initialize(
            header: Ext::B3_HEADER_SINGLE,
            fetcher: Fetcher
          )
            @header = header
            @fetcher = fetcher
          end

          def inject!(digest, env)
            return if digest.nil?

            # Header format:
            #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
            # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
            # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

            # DEV: We need these to be hex encoded
            header = "#{digest.trace_id.to_s(16)}-#{digest.span_id.to_s(16)}"

            if digest.trace_sampling_priority
              sampling_priority = Helpers.clamp_sampling_priority(
                digest.trace_sampling_priority
              )
              header += "-#{sampling_priority}"
            end

            env[@header] = header

            env
          end

          def extract(env)
            # Header format:
            #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
            # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
            # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

            headers = @fetcher.new(env)
            value = headers[@header]
            return if value.nil?

            parts = value.split('-')
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
