require 'set'

require 'ddtrace/context'

module Datadog
  # \ContextFlush is used to cap context size and avoid it using too much memory.
  # It performs memory flushes when required.
  class ContextFlush
    # by default, soft and hard limits are the same
    DEFAULT_MAX_SPANS_BEFORE_PARTIAL_FLUSH = Datadog::Context::DEFAULT_MAX_LENGTH
    # by default, never do a partial flush
    DEFAULT_MIN_SPANS_BEFORE_PARTIAL_FLUSH = Datadog::Context::DEFAULT_MAX_LENGTH
    # timeout should be lower than the trace agent window
    DEFAULT_PARTIAL_FLUSH_TIMEOUT = 10

    private_constant :DEFAULT_MAX_SPANS_BEFORE_PARTIAL_FLUSH
    private_constant :DEFAULT_MIN_SPANS_BEFORE_PARTIAL_FLUSH
    private_constant :DEFAULT_PARTIAL_FLUSH_TIMEOUT

    def initialize(options = {})
      # max_spans_before_partial_flush is the amount of spans collected before
      # the context starts to partially flush parts of traces. With a setting of 10k,
      # the memory overhead is about 10Mb per thread/context (depends on spans metadata,
      # this is just an order of magnitude).
      @max_spans_before_partial_flush = options.fetch(:max_spans_before_partial_flush,
                                                      DEFAULT_MAX_SPANS_BEFORE_PARTIAL_FLUSH)
      # min_spans_before_partial_flush is the minimum number of spans required
      # for a partial flush to happen on a timeout. This is to prevent partial flush
      # of traces which last a very long time but yet have few spans.
      @min_spans_before_partial_flush = options.fetch(:min_spans_before_partial_flush,
                                                      DEFAULT_MIN_SPANS_BEFORE_PARTIAL_FLUSH)
      # partial_flush_timeout is the limit (in seconds) above which the context
      # considers flushing parts of the trace. Partial flushes should not be done too
      # late else the agent rejects them with a "too far in the past" error.
      @partial_flush_timeout = options.fetch(:partial_flush_timeout,
                                             DEFAULT_PARTIAL_FLUSH_TIMEOUT)
      @partial_traces = []
    end

    def add_children(m, spans, ids, leaf)
      spans << leaf
      ids.add(leaf.span_id)

      if m[leaf.span_id]
        m[leaf.span_id].each do |sub|
          add_children(m, spans, ids, sub)
        end
      end
    end

    def partial_traces(context)
      # 1st step, taint all parents of an unfinished span as unflushable
      unflushable_ids = Set.new

      context.each_span do |span|
        next if span.finished? || unflushable_ids.include?(span.span_id)
        unflushable_ids.add span.span_id
        while span.parent
          span = span.parent
          unflushable_ids.add span.span_id
        end
      end

      # 2nd step, find all spans which are at the border between flushable and unflushable
      # Along the road, collect a reverse-tree which allows direct walking from parents to
      # children but only for the ones we're interested it.
      roots = []
      children_map = {}
      context.each_span do |span|
        # There's no point in trying to put the real root in those partial roots, if
        # it's flushable, the default algorithm would figure way more quickly.
        if span.parent && !unflushable_ids.include?(span.span_id)
          if unflushable_ids.include?(span.parent.span_id)
            # span is flushable but is parent is not
            roots << span
          else
            # span is flushable and its parent is too, build the reverse
            # parent to child map for this one, it will be useful
            children_map[span.parent.span_id] ||= []
            children_map[span.parent.span_id] << span
          end
        end
      end

      # 3rd step, find all children, as this can be costly, only perform it for partial roots
      partial_traces = []
      all_ids = Set.new
      roots.each do |root|
        spans = []
        add_children(children_map, spans, all_ids, root)
        partial_traces << spans
      end

      return [nil, nil] if partial_traces.empty?
      [partial_traces, all_ids]
    end

    def partial_flush(context)
      traces, flushed_ids = partial_traces(context)
      return nil unless traces && flushed_ids

      # We need to reject by span ID and not by value, because a span
      # value may be altered (typical example: it's finished by some other thread)
      # since we lock only the context, not all the spans which belong to it.
      context.delete_span_if { |span| flushed_ids.include? span.span_id }
      traces
    end

    # Performs an operation which each partial trace it can get from the context.
    def each_partial_trace(context)
      start_time = context.start_time
      length = context.length
      # Stop and do not flush anything if there are not enough spans.
      return if length <= @min_spans_before_partial_flush
      # If there are enough spans, but not too many, check for start time.
      # If timeout is not given or 0, then wait
      return if length <= @max_spans_before_partial_flush &&
                (@partial_flush_timeout.nil? || @partial_flush_timeout <= 0 ||
                 (start_time && start_time > Time.now.utc - @partial_flush_timeout))
      # Here, either the trace is old or we have too many spans, flush it.
      traces = partial_flush(context)
      return unless traces
      traces.each do |trace|
        yield trace
      end
    end

    private :add_children
    private :partial_traces
    private :partial_flush
  end
end
