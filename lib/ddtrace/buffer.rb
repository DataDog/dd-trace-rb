require 'thread'

module Datadog
  # Trace buffer that stores application traces. The buffer has a maximum size and when
  # the buffer is full, a random trace is discarded. This class is thread-safe and is used
  # automatically by the ``Tracer`` instance when a ``Span`` is finished.
  class TraceBuffer
    def initialize(max_size)
      @max_size = max_size

      @mutex = Mutex.new()
      @traces = []
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
        else
          # we should replace a random trace with the new one
          @traces[rand(len)] = trace
        end
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
        return traces
      end
    end

    def close
      @mutex.synchronize do
        @closed = true
      end
    end
  end
end
