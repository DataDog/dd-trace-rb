# typed: true

module Datadog
  module Tracing
    module Flush
      # Consumes only completed traces (where all spans have finished)
      class Finished
        # Consumes and returns completed traces (where all spans have finished)
        # from the provided \trace_op, if any.
        #
        # Any traces consumed are removed from +trace_op+ as a side effect.
        #
        # @return [TraceSegment] trace to be flushed, or +nil+ if the trace is not finished
        def consume!(trace_op)
          return unless full_flush?(trace_op)

          get_trace(trace_op)
        end

        def full_flush?(trace_op)
          trace_op && trace_op.finished?
        end

        protected

        def get_trace(trace_op)
          trace_op.flush!
        end
      end

      # Performs partial trace flushing to avoid large traces residing in memory for too long
      class Partial
        # Start flushing partial trace after this many active spans in one trace
        DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH = 500

        attr_reader :min_spans_for_partial

        def initialize(options = {})
          @min_spans_for_partial = options.fetch(:min_spans_before_partial_flush, DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH)
        end

        # Consumes and returns completed or partially completed
        # traces from the provided +trace_op+, if any.
        #
        # Partially completed traces, where not all spans have finished,
        # will only be returned if there are at least
        # +@min_spans_for_partial+ finished spans.
        #
        # Any spans consumed are removed from +trace_op+ as a side effect.
        #
        # @return [TraceSegment] partial or complete trace to be flushed, or +nil+ if no spans are finished
        def consume!(trace_op)
          return unless partial_flush?(trace_op)

          get_trace(trace_op)
        end

        def partial_flush?(trace_op)
          return true if trace_op.finished?
          return false if trace_op.finished_span_count < @min_spans_for_partial

          true
        end

        protected

        def get_trace(trace_op)
          trace_op.flush!
        end
      end
    end
  end
end
