# frozen_string_literal: true

require_relative "../../tracing/utils"

module Datadog
  module OpenTelemetry
    module SDK
      # Generates Datadog-compatible trace IDs for OpenTelemetry spans.
      #
      # Reuses the same 128-bit ID format as non-OTel Datadog tracing:
      #   [32-bit seconds since Epoch | 32 zero bits | 64 random bits]
      #
      # When DD_TRACE_128_BIT_TRACEID_GENERATION_ENABLED is false the high 64
      # bits are zero, preserving the OTel 16-byte wire format while keeping
      # backward compatibility with 64-bit Datadog trace IDs.
      class IdGenerator
        class << self
          include ::OpenTelemetry::Trace

          # @return [String] a valid 16-byte trace ID.
          def generate_trace_id
            trace_id = Tracing::Utils::TraceId.next_id
            [
              Tracing::Utils::TraceId.to_high_order(trace_id),
              Tracing::Utils::TraceId.to_low_order(trace_id)
            ].pack("Q>Q>")
          end
        end
      end
    end
  end
end
