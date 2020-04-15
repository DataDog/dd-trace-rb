module Datadog
  module ContextFlush
    # Consumes only completed traces (where all spans have finished)
    class Finished
      # Consumes and returns completed traces (where all spans have finished)
      # from the provided +context+, if any.
      #
      # Any traces consumed are removed from +context+ as a side effect.
      #
      # @return [Array<Span>] trace to be flushed, or +nil+ if the trace is not finished
      def consume!(context)
        trace, sampled = context.get
        trace if sampled
      end
    end

    # Performs partial trace flushing to avoid large traces residing in memory for too long
    class Partial
      # Start flushing partial trace after this many active spans in one trace
      DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH = 500

      def initialize(options = {})
        @min_spans_for_partial = options.fetch(:min_spans_before_partial_flush, DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH)
      end

      # Consumes and returns completed or partially completed
      # traces from the provided +context+, if any.
      #
      # Partially completed traces, where not all spans have finished,
      # will only be returned if there are at least
      # +@min_spans_for_partial+ finished spans.
      #
      # Any spans consumed are removed from +context+ as a side effect.
      #
      # @return [Array<Span>] partial or complete trace to be flushed, or +nil+ if no spans are finished
      def consume!(context)
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
        trace = context.delete_span_if(&:finished?)

        # Ensure that the first span in a partial trace has
        # sampling and origin information.
        if trace[0]
          context.annotate_for_flush!(trace[0])
        else
          Datadog.logger.debug('Tried to retrieve trace from context, but got nothing. ' \
            "Is there another consumer for this context? #{context.trace_id}")
        end

        trace unless trace.empty?
      end
    end
  end
end
