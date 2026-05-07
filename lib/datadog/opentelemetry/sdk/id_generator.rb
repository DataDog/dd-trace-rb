# frozen_string_literal: true

module Datadog
  module OpenTelemetry
    module SDK
      # Generates Datadog-compatible IDs for OpenTelemetry traces.
      # OpenTelemetry traces already produce Datadog-compatible IDs.
      class IdGenerator
        class << self
          include ::OpenTelemetry::Trace

          # Generates a valid trace identifier, a 16-byte string with at least one
          # non-zero byte.
          #
          # @return [String] a valid trace ID.
          def generate_trace_id
            loop do
              id = "\x00".b * 8 + Random.bytes(8)
              return id unless id == INVALID_TRACE_ID
            end
          end
        end
      end
    end
  end
end
