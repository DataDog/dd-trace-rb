require 'thread'
require 'ddtrace/runtime/object_space'

module Datadog
  # Trace buffer that stores application traces. The buffer has a maximum size and when
  # the buffer is full, a random trace is discarded. This class is thread-safe and is used
  # automatically by the ``Tracer`` instance when a ``Span`` is finished.
  class TraceBuffer
    def initialize(max_size)
      @max_size = max_size

      @mutex = Mutex.new()
      @traces = []
      @span_count = 0
      @closed = false
    end

    # Add a new ``trace`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random trace is discarded.
    def push(trace)
      @mutex.synchronize do
        return if @closed
        len = @traces.length
        if len < @max_size || @max_size <= 0
          @traces << trace
          @span_count += trace.length

          measure_accept(trace)
        else
          # we should replace a random trace with the new one
          target = rand(len)
          @span_count -= @traces[target].length
          @traces[target] = trace
          @span_count += trace.length

          measure_accept(trace)
          measure_drop
        end

        measure_queue
      end
    end

    # Return the current number of stored traces.
    def length
      @mutex.synchronize do
        return @traces.length
      end
    end

    # Return if the buffer is empty.
    def empty?
      @mutex.synchronize do
        return @traces.empty?
      end
    end

    # Stored traces are returned and the local buffer is reset.
    def pop
      @mutex.synchronize do
        traces = @traces
        @traces = []
        @span_count = 0

        measure_queue

        return traces
      end
    end

    def close
      @mutex.synchronize do
        @closed = true
      end
    end

    private

    def measure_accept(trace)
      Debug::Health.metrics.queue_accepted(1)
      Debug::Health.metrics.queue_accepted_lengths(trace.length)
      Debug::Health.metrics.queue_accepted_size { measure_trace_size(trace) }
    rescue StandardError => e
      Datadog::Tracer.log.debug("Failed to measure queue accept. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_drop
      Debug::Health.metrics.queue_dropped(1)
    rescue StandardError => e
      Datadog::Tracer.log.debug("Failed to measure queue drop. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_queue
      Debug::Health.metrics.queue_max_length(@max_size)
      Debug::Health.metrics.queue_spans(@span_count)
      Debug::Health.metrics.queue_length(@traces.length)
      Debug::Health.metrics.queue_size { measure_traces_size(@traces) }
    rescue StandardError => e
      Datadog::Tracer.log.debug("Failed to measure queue. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_traces_size(traces)
      traces.inject(Datadog::Runtime::ObjectSpace.estimate_bytesize(traces)) do |sum, trace|
        sum + measure_trace_size(trace)
      end
    end

    def measure_trace_size(trace)
      trace.inject(Datadog::Runtime::ObjectSpace.estimate_bytesize(trace)) do |sum, span|
        sum + Datadog::Runtime::ObjectSpace.estimate_bytesize(span)
      end
    end
  end
end
