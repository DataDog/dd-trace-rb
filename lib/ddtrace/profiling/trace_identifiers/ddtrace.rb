# typed: true
# frozen_string_literal: true

require 'ddtrace/ext/http'

module Datadog
  module Profiling
    module TraceIdentifiers
      # Used by Datadog::Profiling::TraceIdentifiers::Helper to get the trace identifiers (root span id and span id)
      # for a given thread, if there is an active trace for that thread in the supplied tracer object.
      class Ddtrace
        def initialize(tracer:)
          @tracer = (tracer if tracer.respond_to?(:call_context))
        end

        def trace_identifiers_for(thread)
          return unless @tracer

          context = @tracer.call_context(thread)
          return unless context

          span, root_span = context.current_span_and_root_span
          return unless span && root_span

          root_span_id = root_span.span_id || 0
          span_id = span.span_id || 0

          [root_span_id, span_id, maybe_extract_resource(root_span)] if root_span_id != 0 && span_id != 0
        end

        private

        # NOTE: Currently we're only interested in HTTP service endpoints. Over time, this list may be expanded.
        # Resources MUST NOT include personal identifiable information (PII); this should not be the case with
        # ddtrace integrations, but worth mentioning just in case :)
        def maybe_extract_resource(root_span)
          root_span.resource if root_span.span_type == Datadog::Ext::HTTP::TYPE_INBOUND
        end
      end
    end
  end
end
