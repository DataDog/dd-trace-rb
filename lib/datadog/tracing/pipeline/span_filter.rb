# typed: true

require 'set'
require 'datadog/tracing/pipeline/span_processor'

module Datadog
  module Tracing
    module Pipeline
      # SpanFilter implements a processor that filters entire span subtrees
      # This processor executes the configured `operation` for each {Datadog::Tracing::Span}
      # in a {Datadog::Tracing::TraceSegment}.
      #
      # If `operation` returns a truthy value for a span, that span is kept,
      # otherwise the span is removed from the trace.
      #
      # @public_api
      class SpanFilter < SpanProcessor
        # NOTE: this SpanFilter implementation only handles traces in which child spans appear
        # after parent spans in the trace array. If in the future child spans can be before
        # parent spans, then the code below will need to be updated.
        # @!visibility private
        def call(trace)
          deleted = Set.new

          trace.spans.delete_if do |span|
            should_delete = deleted.include?(span.parent_id) || drop_it?(span)
            deleted << span.id if should_delete
            should_delete
          end

          trace
        end

        private

        def drop_it?(span)
          @operation.call(span) rescue false
        end
      end
    end
  end
end
