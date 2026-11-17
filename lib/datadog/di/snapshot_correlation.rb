# frozen_string_literal: true

module Datadog
  module DI
    # The APM trace and span a method-probe snapshot reports, captured
    # together when the sampling gate admitted the probe hit. Either value
    # is nil when no trace or no span was active at admission.
    #
    # @api private
    class SnapshotCorrelation
      # Captures the trace and the span that is active in it.
      #
      # @param trace [Datadog::Tracing::TraceOperation, nil] the APM trace
      #   active at admission
      # @return [SnapshotCorrelation]
      def self.capture(trace)
        new(trace: trace, span: trace&.active_span)
      end

      # Initializes the correlation.
      #
      # @param trace [Datadog::Tracing::TraceOperation, nil] the APM trace
      #   active at admission
      # @param span [Datadog::Tracing::SpanOperation, nil] the span active in
      #   +trace+ at admission
      # @return [void]
      def initialize(trace:, span:)
        @trace = trace
        @span = span
      end

      # The APM trace active at admission, or nil when none was active.
      # @return [Datadog::Tracing::TraceOperation, nil]
      attr_reader :trace

      # The span active in the trace at admission, or nil when none was
      # active.
      # @return [Datadog::Tracing::SpanOperation, nil]
      attr_reader :span
    end
  end
end
