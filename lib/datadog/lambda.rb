# frozen_string_literal: true

require_relative "../datadog"
require_relative "lambda/metrics"

module Datadog
  # AWS Lambda APIs retained from the datadog-lambda gem.
  module Lambda
    @trace_context = nil

    class << self
      # Sends a custom distribution metric to the Datadog Lambda extension.
      # Falls back to the Datadog Forwarder stdout format when the extension is absent.
      # @public_api
      def metric(name, value, time: nil, **tags)
        raise "name must be a string" unless name.is_a?(String)
        raise "value must be a number" unless value.is_a?(Numeric)

        Metrics.distribution(name, value, time: time, tags: tags)
      end

      # Returns the current Datadog trace context for compatibility with datadog-lambda.
      # @public_api
      def trace_context
        active_trace = Tracing.active_trace
        digest = active_trace.to_digest if active_trace.is_a?(Tracing::TraceOperation)
        digest ||= @trace_context
        return {} unless digest

        {
          trace_id: digest.trace_id.to_s,
          parent_id: digest.span_id.to_s,
          sample_mode: digest.trace_sampling_priority,
          source: "ddtrace",
        }
      end

      private

      def record_trace_context(digest)
        @trace_context = digest
      end
    end
  end
end
