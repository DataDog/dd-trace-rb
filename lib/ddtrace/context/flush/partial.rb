module Datadog
  class Context
    module Flush
      # Performs partial trace flushing to avoid large traces residing in memory for too long
      class Partial
        # Start flushing partial trace after this many active spans in one trace
        DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH = 500

        def initialize(options = {})
          @min_spans_for_partial = options.fetch(:min_spans_before_partial_flush, DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH)
        end

        # @return [Array<Span>] partial or complete trace to be flushed, or +nil+ if no spans are finished
        def consume(context)
          trace, sampled = context.get

          return nil unless sampled
          return trace if trace && !trace.empty?

          partial_trace(context)
        end

        private

        def partial_trace(context)
          return nil if context.finished_span_count < @min_spans_for_partial

          finished_spans(context)
        end

        def finished_spans(context)
          trace = context.send(:delete_span_if, &:finished?).tap do |spans|
            # Ensure that the first span in a partial trace has
            # sampling and origin information.
            context.configure_root_span(spans[0]) if spans[0]
          end

          trace unless trace.empty?
        end
      end
    end
  end
end
