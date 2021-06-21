# frozen_string_literal: true

module Datadog
  module Profiling
    module TraceIdentifiers
      # Used by Datadog::Profiling::TraceIdentifiers::Helper to get the trace identifiers (trace id and span id) for a
      # given thread, if there is an active trace for that thread in Datadog.tracer.
      class Ddtrace
        def initialize(tracer: nil)
          @tracer = tracer
        end

        def trace_identifiers_for(thread)
          current_tracer = tracer
          return unless current_tracer

          correlation = current_tracer.active_correlation(thread)
          trace_id = correlation.trace_id
          span_id = correlation.span_id

          [trace_id, span_id] if trace_id && trace_id != 0 && span_id && span_id != 0
        end

        private

        def tracer
          return @tracer if @tracer

          # NOTE: Because the profiler may start working concurrently with tracer initialization,
          # we need to be defensive here.
          return unless Datadog.respond_to?(:tracer)

          tracer = Datadog.tracer
          return unless tracer.respond_to?(:active_correlation)

          @tracer = tracer
        end
      end
    end
  end
end
