require 'thread'
require 'ddtrace/diagnostics/health'
require 'ddtrace/runtime/object_space'

module Datadog
  # Buffer that stores objects. The buffer has a maximum size and when
  # the buffer is full, a random object is discarded. This class is thread-safe.
  class Buffer
    def initialize(max_size)
      @max_size = max_size

      @mutex = Mutex.new
      @items = []
      @closed = false
    end

    # Add a new ``item`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random item is discarded.
    def push(item)
      @mutex.synchronize do
        return if @closed
        full? ? replace!(item) : add!(item)
        item
      end
    end

    # Return the current number of stored items.
    def length
      @mutex.synchronize do
        return @items.length
      end
    end

    # Return if the buffer is empty.
    def empty?
      @mutex.synchronize do
        return @items.empty?
      end
    end

    # Stored items are returned and the local buffer is reset.
    def pop
      @mutex.synchronize do
        drain!
      end
    end

    def close
      @mutex.synchronize do
        @closed = true
      end
    end

    protected

    def full?
      @max_size > 0 && @items.length >= @max_size
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

  # Trace buffer that stores application traces. The buffer has a maximum size and when
  # the buffer is full, a random trace is discarded. This class is thread-safe and is used
  # automatically by the ``Tracer`` instance when a ``Span`` is finished.
  class TraceBuffer < Buffer
    def initialize(max_size)
      super

      # Initialize metric values
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    end

    protected

    def add!(trace)
      super

      # Emit health metrics
      measure_accept(trace)
    end

    def replace!(trace)
      discarded_trace = super

      # Emit health metrics
      measure_accept(trace)
      measure_drop(discarded_trace)

      discarded_trace
    end

    # Stored traces are returned and the local buffer is reset.
    def drain!
      traces = super
      measure_pop(traces)
      traces
    end

    # Aggregate metrics:
    # They reflect buffer activity since last #pop.
    # These may not be as accurate or as granular, but they
    # don't use as much network traffic as live stats.

    def measure_accept(trace)
      @buffer_spans += trace.length
      @buffer_accepted += 1
      @buffer_accepted_lengths += trace.length
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue accept. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_drop(trace)
      @buffer_dropped += 1
      @buffer_spans -= trace.length
      @buffer_accepted_lengths -= trace.length
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue drop. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_pop(traces)
      # Accepted
      Datadog.health_metrics.queue_accepted(@buffer_accepted)
      Datadog.health_metrics.queue_accepted_lengths(@buffer_accepted_lengths)

      # Dropped
      Datadog.health_metrics.queue_dropped(@buffer_dropped)

      # Queue gauges
      Datadog.health_metrics.queue_max_length(@max_size)
      Datadog.health_metrics.queue_spans(@buffer_spans)
      Datadog.health_metrics.queue_length(traces.length)

      # Reset aggregated metrics
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue. Cause: #{e.message} Source: #{e.backtrace.first}")
    end
  end
end
