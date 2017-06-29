require 'thread'

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
  class Context
    def initialize
      @mutex = Mutex.new
      _reset
    end

    def _reset
      @trace = []
      @sampled = false # [TODO:christian]
      @finished_spans = 0
      @current_span = nil
    end

    def current_span
      @mutex.synchronize do
        return @current_span
      end
    end

    def add_span(span)
      @mutex.synchronize do
        @current_span = span
        @sampled = span.sampled
        @trace << span
        span.context = self
      end
    end

    def close_span(span)
      @mutex.synchronize do
        @finished_spans += 1
        # Current span is only meaningful for linear tree-like traces,
        # in other cases, this is just broken and one should rely
        # on per-instrumentation code to retrieve handle parent/child relations.
        @current_span = span.parent

        return if span.tracer.nil?
        return unless span.tracer.debug_logging
        if span.parent.nil? && !finished?
          opened_spans = @trace.length - @finished_spans
          tracer.log.debug("root span #{span.name} closed but has #{opened_spans} unfinished spans:")
          @trace.each do |s|
            tracer.log.debug("unfinished span: #{s}") unless s.is_finished
          end
        end
      end
    end

    def _is_finished
      @finished_spans > 0 && @trace.length == @finished_spans
    end

    def finished?
      @mutex.synchronize do
        return is_finished
      end
    end

    def sampled?
      @mutex.synchronize do
        return @sampled
      end
    end

    def get
      @mutex.synchronize do
        return nil, nil unless is_finished

        trace = @trace
        sampled = @sampled
        reset
        return trace, sampled
      end
    end

    private :_reset
    private :_is_finished
  end

  # ThreadLocalContext can be used as a tracer global reference to create
  # a different \Context for each thread. In synchronous tracer, this
  # is required to prevent multiple threads sharing the same \Context
  # in different executions.
  class ThreadLocalContext
    def initialize
      set(Datadog::Context.new)
    end

    def set(ctx)
      Thread.current[:datadog_context] = ctx
    end

    def get()
      Thread.current[:datadog_context] ||= Datadog::Context.new
    end
  end
end
