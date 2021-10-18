# typed: true
require 'ddtrace/diagnostics/health'

# Trace buffer that accumulates traces for a consumer.
# Consumption can happen from a different thread.
module Datadog
  # Buffer that stores objects. The buffer has a maximum size and when
  # the buffer is full, a random object is discarded.
  class Buffer
    def initialize(max_size)
      @max_size = max_size
      @items = []
      @closed = false
    end

    # Add a new ``item`` in the local queue. This method doesn't block the execution
    # even if the buffer is full.
    #
    # When the buffer is full, we try to ensure that we are fairly sampling newly
    # pushed traces by randomly inserting them into the buffer slots. This discards
    # old traces randomly while trying to ensure that recent traces are still captured.
    def push(item)
      return if closed?

      full? ? replace!(item) : add!(item)
      item
    end

    # A bulk push alternative to +#push+. Use this method if
    # pushing more than one item for efficiency.
    def concat(items)
      return if closed?

      # Segment items into underflow and overflow
      underflow, overflow = overflow_segments(items)

      # Concatenate items do not exceed capacity.
      add_all!(underflow) unless underflow.nil?

      # Iteratively replace items, to ensure pseudo-random replacement.
      overflow.each { |item| replace!(item) } unless overflow.nil?
    end

    # Stored items are returned and the local buffer is reset.
    def pop
      drain!
    end

    # Return the current number of stored traces.
    def length
      @items.length
    end

    # Return if the buffer is empty.
    def empty?
      @items.empty?
    end

    # Closes this buffer, preventing further pushing.
    # Draining is still allowed.
    def close
      @closed = true
    end

    def closed?
      @closed
    end

    protected

    # Segment items into two segments: underflow and overflow.
    # Underflow are items that will fit into buffer.
    # Overflow are items that will exceed capacity, after underflow is added.
    # Returns each array, and nil if there is no underflow/overflow.
    def overflow_segments(items)
      underflow = nil
      overflow = nil

      overflow_size = @max_size > 0 ? (@items.length + items.length) - @max_size : 0

      if overflow_size > 0
        # Items will overflow
        if overflow_size < items.length
          # Partial overflow
          underflow_end_index = items.length - overflow_size - 1
          underflow = items[0..underflow_end_index]
          overflow = items[(underflow_end_index + 1)..-1]
        else
          # Total overflow
          overflow = items
        end
      else
        # Items do not exceed capacity.
        underflow = items
      end

      [underflow, overflow]
    end

    def full?
      @max_size > 0 && @items.length >= @max_size
    end

    def add_all!(items)
      @items.concat(items)
    end

    def add!(item)
      @items << item
    end

    def replace!(item)
      # Choose random item to be replaced
      replace_index = rand(@items.length)

      # Replace random item
      discarded_item = @items[replace_index]
      @items[replace_index] = item

      # Return discarded item
      discarded_item
    end

    def drain!
      items = @items
      @items = []
      items
    end
  end

  # Buffer that stores objects, has a maximum size, and
  # can be safely used concurrently on any environment.
  #
  # This implementation uses a {Mutex} around public methods, incurring
  # overhead in order to ensure thread-safety.
  #
  # This is implementation is recommended for non-CRuby environments.
  # If using CRuby, {Datadog::CRubyBuffer} is a faster implementation with minimal compromise.
  class ThreadSafeBuffer < Buffer
    def initialize(max_size)
      super

      @mutex = Mutex.new
    end

    # Add a new ``item`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random item is discarded.
    def push(item)
      synchronize { super }
    end

    def concat(items)
      synchronize { super }
    end

    # Return the current number of stored traces.
    def length
      synchronize { super }
    end

    # Return if the buffer is empty.
    def empty?
      synchronize { super }
    end

    # Stored traces are returned and the local buffer is reset.
    def pop
      synchronize { super }
    end

    def close
      synchronize { super }
    end

    def synchronize(&block)
      @mutex.synchronize(&block)
    end
  end

  # Buffer that stores objects, has a maximum size, and
  # can be safely used concurrently with CRuby.
  #
  # Because singular +Array+ operations are thread-safe in CRuby,
  # we can implement the trace buffer without an explicit lock,
  # while making the compromise of allowing the buffer to go
  # over its maximum limit under extreme circumstances.
  #
  # On the following scenario:
  # * 4.5 million spans/second.
  # * Pushed into a single CRubyTraceBuffer from 1000 threads.
  #
  # This implementation allocates less memory and is faster
  # than {Datadog::ThreadSafeBuffer}.
  #
  # @see spec/ddtrace/benchmark/buffer_benchmark_spec.rb Buffer benchmarks
  # @see https://github.com/ruby-concurrency/concurrent-ruby/blob/c1114a0c6891d9634f019f1f9fe58dcae8658964/lib/concurrent-ruby/concurrent/array.rb#L23-L27
  class CRubyBuffer < Buffer
    # A very large number to allow us to effectively
    # drop all items when invoking `slice!(i, FIXNUM_MAX)`.
    FIXNUM_MAX = (1 << 62) - 1

    # Add a new ``trace`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random trace is discarded.
    def replace!(item)
      # Ensure buffer stays within +max_size+ items.
      # This can happen when there's concurrent modification
      # between a call the check in `full?` and the `add!` call in
      # `full? ? replace!(item) : add!(item)`.
      #
      # We can still have `@items.size > @max_size` for a short period of
      # time, but we will always try to correct it here.
      #
      # `slice!` is performed before `delete_at` & `<<` to avoid always
      # removing the item that was just inserted.
      #
      # DEV: `slice!` with two integer arguments is ~10% faster than
      # `slice!` with a {Range} argument.
      @items.slice!(@max_size, FIXNUM_MAX)

      # We should replace a random trace with the new one
      replace_index = rand(@max_size)
      @items[replace_index] = item
    end
  end

  # Health metrics for trace buffers.
  module MeasuredBuffer
    include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)

    def initialize(*_)
      super

      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    end

    def add!(trace)
      super

      # Emit health metrics
      measure_accept(trace)
    end

    def add_all!(traces)
      super

      # Emit health metrics
      traces.each { |trace| measure_accept(trace) }
    end

    def replace!(trace)
      discarded_trace = super

      # Emit health metrics
      measure_accept(trace)
      measure_drop(discarded_trace) if discarded_trace

      discarded_trace
    end

    # Stored traces are returned and the local buffer is reset.
    def drain!
      traces = super
      measure_pop(traces)
      traces
    end

    def measure_accept(trace)
      @buffer_accepted += 1
      @buffer_accepted_lengths += trace.length

      @buffer_spans += trace.length
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue accept. Cause: #{e.message} Source: #{Array(e.backtrace).first}")
    end

    def measure_drop(trace)
      @buffer_dropped += 1

      @buffer_spans -= trace.length
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue drop. Cause: #{e.message} Source: #{Array(e.backtrace).first}")
    end

    def measure_pop(traces)
      # Accepted, cumulative totals
      Datadog.health_metrics.queue_accepted(@buffer_accepted)
      Datadog.health_metrics.queue_accepted_lengths(@buffer_accepted_lengths)

      # Dropped, cumulative totals
      Datadog.health_metrics.queue_dropped(@buffer_dropped)
      # TODO: are we missing a +queue_dropped_lengths+ metric?

      # Queue gauges, current values
      Datadog.health_metrics.queue_max_length(@max_size)
      Datadog.health_metrics.queue_spans(@buffer_spans)
      Datadog.health_metrics.queue_length(traces.length)

      # Reset aggregated metrics
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue. Cause: #{e.message} Source: #{Array(e.backtrace).first}")
    end
  end

  # Trace buffer that stores application traces, has a maximum size, and
  # can be safely used concurrently on any environment.
  #
  # @see {Datadog::ThreadSafeBuffer}
  class ThreadSafeTraceBuffer < ThreadSafeBuffer
    prepend MeasuredBuffer
  end

  # Trace buffer that stores application traces, has a maximum size, and
  # can be safely used concurrently with CRuby.
  #
  # @see {Datadog::CRubyBuffer}
  class CRubyTraceBuffer < CRubyBuffer
    prepend MeasuredBuffer
  end

  # Trace buffer that stores application traces. The buffer has a maximum size and when
  # the buffer is full, a random trace is discarded. This class is thread-safe and is used
  # automatically by the ``Tracer`` instance when a ``Span`` is finished.
  #
  # We choose the default TraceBuffer implementation for current platform dynamically here.
  #
  # TODO We should restructure this module, so that classes are not declared at top-level ::Datadog.
  # TODO Making such a change is potentially breaking for users manually configuring the tracer.
  TraceBuffer = if Datadog::Core::Environment::Ext::RUBY_ENGINE == 'ruby'
                  CRubyTraceBuffer
                else
                  ThreadSafeTraceBuffer
                end
end
