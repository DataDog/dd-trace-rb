# frozen_string_literal: true

require_relative 'helpers'
require_relative '../trace_digest'

module Datadog
  module Tracing
    module Distributed
      # B3 single header-style trace propagation.
      #
      # DEV: Format:
      # DEV:   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
      # DEV: https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
      # DEV: `{SamplingState}` and `{ParentSpanId}` are optional
      #
      # @see https://github.com/openzipkin/b3-propagation#single-header
      class B3Single
        B3_SINGLE_HEADER_KEY = 'b3'

        def initialize(fetcher:, key: B3_SINGLE_HEADER_KEY)
          @key = key
          @fetcher = fetcher
        end

        def inject!(digest, env)
          return if digest.nil?

          # DEV: We need these to be hex encoded
          value = "#{digest.trace_id.to_s(16)}-#{digest.span_id.to_s(16)}"

          if digest.trace_sampling_priority
            sampling_priority = Helpers.clamp_sampling_priority(
              digest.trace_sampling_priority
            )
            value += "-#{sampling_priority}"
          end

          env[@key] = value
          env
        end

        def extract(env)
          fetcher = @fetcher.new(env)
          value = fetcher[@key]

          return unless value

          parts = value.split('-')
          trace_id = Helpers.value_to_id(parts[0], base: 16) unless parts.empty?
          span_id = Helpers.value_to_id(parts[1], base: 16) if parts.length > 1
          sampling_priority = Helpers.value_to_number(parts[2]) if parts.length > 2

          # Return if this propagation is not valid
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
