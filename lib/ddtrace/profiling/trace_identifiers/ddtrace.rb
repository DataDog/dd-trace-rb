# frozen_string_literal: true

module Datadog
  module Profiling
    module TraceIdentifiers
      # Used by Datadog::Profiling::TraceIdentifiers::Helper to get the trace identifiers (trace id and span id) for a
      # given thread, if there is an active trace for that thread in Datadog.tracer.
      class Ddtrace
        def initialize(tracer: nil)
          @tracer = (tracer if tracer.respond_to?(:active_correlation))
        end

        def trace_identifiers_for(thread)
          return unless @tracer

          correlation = @tracer.active_correlation(thread)
          trace_id = correlation.trace_id
          span_id = correlation.span_id

          [trace_id, span_id] if trace_id && trace_id != 0 && span_id && span_id != 0
        end
      end
    end
  end
end
