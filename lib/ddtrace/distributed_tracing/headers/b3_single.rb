# typed: true
require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/headers'
require 'ddtrace/distributed_tracing/headers/helpers'
require 'ddtrace/trace_digest'

module Datadog
  module DistributedTracing
    module Headers
      # B3Single provides helpers to inject or extract headers for B3 single header style headers
      module B3Single
        include Ext::DistributedTracing

        def self.inject!(digest, env)
          return if digest.nil?

          # Header format:
          #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
          # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
          # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

          # DEV: We need these to be hex encoded
          header = "#{digest.trace_id.to_s(16)}-#{digest.span_id.to_s(16)}"

          if digest.trace_sampling_priority
            sampling_priority = DistributedTracing::Headers::Helpers.clamp_sampling_priority(
              digest.trace_sampling_priority
            )
            header += "-#{sampling_priority}"
          end

          env[B3_HEADER_SINGLE] = header

          env
        end

        def self.extract(env)
          # Header format:
          #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
          # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
          # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

          headers = Headers.new(env)
          value = headers.header(B3_HEADER_SINGLE)
          return if value.nil?

          parts = value.split('-')
          trace_id = headers.value_to_id(parts[0], 16) unless parts.empty?
          span_id = headers.value_to_id(parts[1], 16) if parts.length > 1
          sampling_priority = headers.value_to_number(parts[2]) if parts.length > 2

          # Return early if this propagation is not valid
          return unless trace_id && span_id

          ::Datadog::TraceDigest.new(
            span_id: span_id,
            trace_id: trace_id,
            trace_sampling_priority: sampling_priority
          )
        end
      end
    end
  end
end
