require 'thread'

module Datadog
  # Buffer used to store active spans
  class SpanBuffer
    # ensure that a new SpanBuffer clears the thread spans
    def initialize
      Thread.current[:datadog_span] = nil
    end

    # Set the current active span.
    def set(span)
      Thread.current[:datadog_span] = span
    end

    # Return the current active span or nil.
    def get
      Thread.current[:datadog_span]
    end

    # Pop the current active span.
    def pop
      span = get()
      set(nil)
      span
    end
  end

  # TraceBuffer buffers a maximum number of traces waiting
  # to be sent to the app
  class TraceBuffer
    def initialize(max_size)
      @max_size = max_size

      @mutex = Mutex.new()
      @traces = []
    end

    def push(trace)
      @mutex.synchronize do
        len = @traces.length()
        if len < @max_size
          @traces << trace
        else
          # drop a random one
          @traces[rand(len)] = trace
        end
      end
    end

    def length
      @mutex.synchronize do
        return @traces.length
      end
    end

    def pop
      @mutex.synchronize do
        # FIXME: reuse array?
        traces = @traces
        @traces = []
        return traces
      end
    end
  end
end
