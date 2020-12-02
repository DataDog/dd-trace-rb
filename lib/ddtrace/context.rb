require 'thread'
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
    def current_span
      @mutex.synchronize do
        return @current_span
      end
    end

    def current_root_span
      @mutex.synchronize do
        return @current_root_span
      end
    end

    # Add a span to the context trace list, keeping it as the last active span.
    def add_span(span)
      @mutex.synchronize do
        # If hitting the hard limit, just drop spans. This is really a rare case
        # as it means despite the soft limit, the hard limit is reached, so the trace
        # by default has 10000 spans, all of which belong to unfinished parts of a
        # larger trace. This is a catch-all to reduce global memory usage.
        if @max_length > 0 && @trace.length >= @max_length
          # Detach the span from any context, it's being dropped and ignored.
          span.context = nil
          Datadog.logger.debug("context full, ignoring span #{span.name}")

          # If overflow has already occurred, don't send this metric.
          # Prevents metrics spam if buffer repeatedly overflows for the same trace.
          unless @overflow
            Datadog.health_metrics.error_context_overflow(1, tags: ["max_length:#{@max_length}"])
            @overflow = true
          end

          return
        end
        set_current_span(span)
        @current_root_span = span if @trace.empty?
        @trace << span
        span.context = self
      end
    end

    # Mark a span as a finished, increasing the internal counter to prevent
    # cycles inside _trace list.
    def close_span(span)
      @mutex.synchronize do
        @finished_spans += 1
        # Current span is only meaningful for linear tree-like traces,
        # in other cases, this is just broken and one should rely
        # on per-instrumentation code to retrieve handle parent/child relations.
        set_current_span(span.parent)
        return if span.tracer.nil?
        if span.parent.nil? && !all_spans_finished?
          if Datadog.configuration.diagnostics.debug
            opened_spans = @trace.length - @finished_spans
            Datadog.logger.debug("root span #{span.name} closed but has #{opened_spans} unfinished spans:")
          end

          @trace.reject(&:finished?).group_by(&:name).each do |unfinished_span_name, unfinished_spans|
            Datadog.logger.debug("unfinished span: #{unfinished_spans.first}") if Datadog.configuration.diagnostics.debug
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
        annotate_for_flush!(@current_root_span)

        reset
        [trace, sampled]
      end
    end

    # Delete any span matching the condition. This is thread safe.
    #
    # @return [Array<Span>] deleted spans
    def delete_span_if
      @mutex.synchronize do
        [].tap do |deleted_spans|
          @trace.delete_if do |span|
            finished = span.finished?

            next unless yield span

            deleted_spans << span

            # We need to detach the span from the context, else, some code
            # finishing it afterwards would mess up with the number of
            # finished_spans and possibly cause other side effects.
            span.context = nil
            # Acknowledge there's one span less to finish, if needed.
            # It's very important to keep this balanced.
            @finished_spans -= 1 if finished

            true
          end
        end
      end
    end

    # Set tags to root span required for flush
    def annotate_for_flush!(span)
      attach_sampling_priority(span) if @sampled && @sampling_priority
      attach_origin(span) if @origin
    end

    # Return a string representation of the context.
    def to_s
      @mutex.synchronize do
        # rubocop:disable Metrics/LineLength
        "Context(trace.length:#{@trace.length},sampled:#{@sampled},finished_spans:#{@finished_spans},current_span:#{@current_span})"
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
      @current_span = nil
      @current_root_span = nil
      @overflow = false
    end

    def set_current_span(span)
      @current_span = span
      if span
        @parent_trace_id = span.trace_id
        @parent_span_id = span.span_id
        @sampled = span.sampled
      else
        @parent_span_id = nil
      end
    end

    # Returns if the trace for the current Context is finished or not.
    # Low-level internal function, not thread-safe.
    def all_spans_finished?
      @finished_spans > 0 && @trace.length == @finished_spans
    end

    def attach_sampling_priority(span)
      span.set_metric(
        Ext::DistributedTracing::SAMPLING_PRIORITY_KEY,
        @sampling_priority
      )
    end

    def attach_origin(span)
      span.set_tag(
        Ext::DistributedTracing::ORIGIN_KEY,
        @origin
      )
    end

    # Return the start time of the root span, or nil if there are no spans or this is undefined.
    def start_time
      @mutex.synchronize do
        return nil if @trace.empty?
        @trace[0].start_time
      end
    end

    # Return the length of the current trace held by this context.
    def length
      @mutex.synchronize do
        @trace.length
      end
    end

    # Iterate on each span within the trace. This is thread safe.
    def each_span
      @mutex.synchronize do
        @trace.each do |span|
          yield span
        end
      end
    end
  end
end
