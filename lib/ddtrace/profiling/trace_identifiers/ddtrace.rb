# typed: true
# frozen_string_literal: true

require 'ddtrace/ext/http'

module Datadog
  module Profiling
    module TraceIdentifiers
      # Used by Datadog::Profiling::TraceIdentifiers::Helper to get the trace identifiers (trace id and span id) for a
      # given thread, if there is an active trace for that thread in Datadog.tracer.
      class Ddtrace
        def initialize(tracer: nil)
          @tracer = (tracer if tracer.respond_to?(:call_context))
        end

        def trace_identifiers_for(thread)
          return unless @tracer

          context = @tracer.call_context(thread)
          return unless context

          trace_id = context.trace_id || 0
          span_id = context.span_id || 0

          [trace_id, span_id, maybe_extract_resource(context.current_root_span)] if trace_id != 0 && span_id != 0
        end

        private

        # NOTE: Currently we're only interested in HTTP service endpoints. Over time, this list may be expanded.
        # Resources MUST NOT include personal identifiable information (PII); this should not be the case with
        # ddtrace integrations, but worth mentioning just in case :)
        def maybe_extract_resource(root_span)
          return unless root_span

          root_span.resource_container if root_span.span_type == Datadog::Ext::HTTP::TYPE_INBOUND
        end
      end
    end
  end
end
