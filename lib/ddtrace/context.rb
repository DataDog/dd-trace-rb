# typed: true
require 'ddtrace/diagnostics/health'

require 'ddtrace/context_flush'
require 'ddtrace/context_provider'
require 'ddtrace/utils/forking'

module Datadog
  # \Context is used to keep track of a hierarchy of spans for the current
  # execution flow. During each logical execution, the same \Context is
  # used to represent a single logical trace, even if the trace is built
  # asynchronously.
  #
  # A single code execution may use multiple \Context if part of the execution
  # must not be related to the current tracing. As example, a delayed job may
  # compose a standalone trace instead of being related to the same trace that
  # generates the job itself. On the other hand, if it's part of the same
  # \Context, it will be related to the original trace.
  #
  # This data structure is thread-safe.
  # rubocop:disable Metrics/ClassLength
  class Context
    include Datadog::Utils::Forking

    # 100k spans is about a 100Mb footprint
    DEFAULT_MAX_LENGTH = 100_000

    attr_reader :max_length

    # Initialize a new thread-safe \Context.
    def initialize(options = {})
      @mutex = Mutex.new
      # max_length is the amount of spans above which, for a given trace,
      # the context will simply drop and ignore spans, avoiding high memory usage.
      @max_length = options.fetch(:max_length, DEFAULT_MAX_LENGTH)
      reset(options)
    end

    def trace_id
      @mutex.synchronize do
        @parent_trace_id
      end
    end

    def span_id
      @mutex.synchronize do
        @parent_span_id
      end
    end

    def sampling_priority
      @mutex.synchronize do
        @sampling_priority
      end
    end

    def sampling_priority=(priority)
      @mutex.synchronize do
        @sampling_priority = priority
      end
    end

    def origin
      @mutex.synchronize do
        @origin
      end
    end

    def origin=(origin)
      @mutex.synchronize do
        @origin = origin
      end
    end

    # Return the last active span that corresponds to the last inserted
    # item in the trace list. This cannot be considered as the current active
    # span in asynchronous environments, because some spans can be closed
    # earlier while child spans still need to finish their traced execution.
    def current_span_op
      @mutex.synchronize do
        @current_span_op
      end
    end
    alias current_span current_span_op

    def current_root_span_op
      @mutex.synchronize do
        @current_root_span_op
      end
    end
    alias current_root_span current_root_span_op

    # Same as calling #current_span and #current_root_span, but works atomically thus preventing races when we need to
    # retrieve both
    def current_span_and_root_span_ops
      @mutex.synchronize do
        [@current_span_op, @current_root_span_op]
      end
    end
    alias current_span_and_root_span current_span_and_root_span_ops

    def add_span(span_op)
      @mutex.synchronize do
        # If hitting the hard limit, just drop spans. This is really a rare case
        # as it means despite the soft limit, the hard limit is reached, so the trace
        # by default has 10000 spans, all of which belong to unfinished parts of a
        # larger trace. This is a catch-all to reduce global memory usage.
        if full?
          Datadog.logger.debug("context full, ignoring span #{span_op.name}")

          # If overflow has already occurred, don't send this metric.
          # Prevents metrics spam if buffer repeatedly overflows for the same trace.
          unless @overflow
            Datadog.health_metrics.error_context_overflow(1, tags: ["max_length:#{@max_length}"])
            @overflow = true
          end

          return false
        end

        # Add the span to the context
        self.current_span_op = span_op
        @current_root_span_op = span_op if @trace.empty?
        @trace << span_op

        true
      end
    end

    # Mark a span as a finished, increasing the internal counter to prevent
    # cycles inside _trace list.
    def close_span(span_op)
      @mutex.synchronize do
        @finished_spans += 1

        # Find the new current span: it should be an ancestor that is not finished.
        # This is because it's possible that a parent span will finish before a child.
        # If this happens, we don't want to set the current span to a completed span.
        parent = span_op.parent
        parent = parent.parent while !parent.nil? && parent.finished?

        # Current span is only meaningful for linear tree-like traces.
        # In other cases, this is just broken and one should rely
        # on per-instrumentation code to handle parent/child relations.
        self.current_span_op = parent

        # If root span has been closed and spans are still unfinished...
        # ...emit some warnings/metrics to bring attention to this.
        # All spans should be closed when the root span closes.
        # Otherwise traces can leak, or be associated incorrectly.
        if parent.nil? && !all_spans_finished?
          if Datadog.configuration.diagnostics.debug
            opened_spans = @trace.length - @finished_spans
            Datadog.logger.debug("Root span #{span_op.name} closed but has #{opened_spans} unfinished spans:")
          end

          @trace.reject(&:finished?).group_by(&:name).each do |unfinished_span_name, unfinished_spans|
            Datadog.logger.debug("Unfinished span: #{unfinished_spans.first}") if Datadog.configuration.diagnostics.debug
            Datadog.health_metrics.error_unfinished_spans(
              unfinished_spans.length,
              tags: ["name:#{unfinished_span_name}"]
            )
          end
        end
      end
    end

    # Returns if the trace for the current Context is finished or not. A \Context
    # is considered finished if all spans in this context are finished.
    def finished?
      @mutex.synchronize do
        return all_spans_finished?
      end
    end

    # @@return [Numeric] numbers of finished spans
    def finished_span_count
      @mutex.synchronize do
        @finished_spans
      end
    end

    # Returns true if the context is sampled, that is, if it should be kept
    # and sent to the trace agent.
    def sampled?
      @mutex.synchronize do
        return @sampled
      end
    end

    # Returns both the trace list generated in the current context and
    # if the context is sampled or not.
    #
    # It returns +[nil,@sampled]+ if the \Context is
    # not finished.
    #
    # If a trace is returned, the \Context will be reset so that it
    # can be re-used immediately.
    #
    # This operation is thread-safe.
    #
    # @return [Array<Array<Span>, Boolean>] finished trace and sampled flag
    def get
      @mutex.synchronize do
        trace = @trace
        sampled = @sampled

        # still return sampled attribute, even if context is not finished
        return nil, sampled unless all_spans_finished?

        # Root span is finished at this point, we can configure it
        annotate_for_flush!(@current_root_span_op)

        # Allow caller to modify trace before context is reset
        yield(trace) if block_given?

        # Reset the context for re-use.
        reset

        # Return Span measurements and whether it was sampled.
        [trace.collect(&:span), sampled]
      end
    end

    # Delete any span matching the condition. This is thread safe.
    #
    # @return [Array<Span>] deleted spans
    def delete_span_if
      @mutex.synchronize do
        deleted_spans = []
        return deleted_spans unless block_given?

        @trace.delete_if do |span_op|
          finished = span_op.finished?

          # Check condition
          next unless yield(span_op)

          deleted_spans << span_op.span

          # Acknowledge there's one span less to finish, if needed.
          # It's very important to keep this balanced.
          @finished_spans -= 1 if finished

          true
        end

        deleted_spans
      end
    end

    # Set tags to root span required for flush
    def annotate_for_flush!(span_op)
      attach_sampling_priority(span_op) if @sampled && @sampling_priority
      attach_origin(span_op) if @origin
    end

    def attach_sampling_priority(span_op)
      span_op.set_metric(
        Ext::DistributedTracing::SAMPLING_PRIORITY_KEY,
        @sampling_priority
      )
    end

    def attach_origin(span_op)
      span_op.set_tag(
        Ext::DistributedTracing::ORIGIN_KEY,
        @origin
      )
    end

    # Return a string representation of the context.
    def to_s
      @mutex.synchronize do
        # rubocop:disable Layout/LineLength
        "Context(trace.length:#{@trace.length},sampled:#{@sampled},finished_spans:#{@finished_spans},current_span:#{@current_span_op})"
      end
    end

    # Generates equivalent context for forked processes.
    #
    # When Context from parent process is forked, child process
    # should have a Context belonging to the same trace but not
    # have the parent process spans.
    def fork_clone
      self.class.new(
        trace_id: trace_id,
        span_id: span_id,
        sampled: sampled?,
        sampling_priority: sampling_priority,
        origin: origin
      )
    end

    private

    def reset(options = {})
      @trace = []
      @parent_trace_id = options.fetch(:trace_id, nil)
      @parent_span_id = options.fetch(:span_id, nil)
      @sampled = options.fetch(:sampled, false)
      @sampling_priority = options.fetch(:sampling_priority, nil)
      @origin = options.fetch(:origin, nil)
      @finished_spans = 0
      @current_span_op = nil
      @current_root_span_op = nil
      @overflow = false
    end

    def current_span_op=(span_op)
      @current_span_op = span_op
      if span_op
        @parent_trace_id = span_op.trace_id
        @parent_span_id = span_op.span_id
        @sampled = span_op.sampled
      else
        @parent_span_id = nil
      end
    end

    # Returns true if the context is full
    # and cannot accept any more spans.
    def full?
      @max_length > 0 && @trace.length >= @max_length
    end

    # Returns if the trace for the current Context is finished or not.
    # Low-level internal function, not thread-safe.
    def all_spans_finished?
      @finished_spans > 0 && @trace.length == @finished_spans
    end
  end
end
