# frozen_string_literal: true

require_relative '../../tracing'
require_relative '../../tracing/metadata/ext'

module Datadog
  module Profiling
    module TraceIdentifiers
      # Used by Datadog::Profiling::TraceIdentifiers::Helper to get the trace identifiers (root span id and span id)
      # for a given thread, if there is an active trace for that thread in the supplied tracer object.
      class Ddtrace
        def initialize(tracer:)
          @tracer = (tracer if tracer.respond_to?(:active_trace))
        end

        def trace_identifiers_for(thread)
          return unless @tracer

          trace = @tracer.active_trace(thread)
          return unless trace

          root_span = trace.send(:root_span)
          span = trace.active_span
          return unless span && root_span

          root_span_id = root_span.id || 0
          span_id = span.id || 0

          [root_span_id, span_id, maybe_extract_resource(trace, root_span)] if root_span_id != 0 && span_id != 0
        end

        private

        # NOTE: Currently we're only interested in HTTP service endpoints. Over time, this list may be expanded.
        # Resources MUST NOT include personal identifiable information (PII); this should not be the case with
        # ddtrace integrations, but worth mentioning just in case :)
        def maybe_extract_resource(trace, root_span)
          trace.resource if root_span.span_type == Tracing::Metadata::Ext::HTTP::TYPE_INBOUND
        end
      end
    end
  end
end
