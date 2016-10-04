require 'ddtrace/transport'

module Datadog
  # Writer buffer and periodically sends traces to the server.
  class Writer
    def initialize(options = {})
      @transport = options[:transport] || Datadog::Transport.new('localhost', '7777')
      @trace_buffer = TraceBuffer.new(100)

      @flush_interval = 1
      @traces_flushed = 0

      spawn(@flush_interval)
    end

    # spawn will spawn a thread that will periodically flush to the server.
    def spawn(interval)
      Thread.new do
        loop do
          sleep(interval)
          flush
        end
      end
    end

    # flush will trigger a flush to the server.
    def flush
      traces = @trace_buffer.pop
      unless traces.empty?
        spans = traces.flatten
        # FIXME[matt] submit as an array of traces or a flat array of spans?
        #
        @transport.write(spans)          # FIXME matt: if there's an error, requeue
        @traces_flushed += traces.length # FIXME matt: synchornize?
      end
    end

    # write will queue the trace for submission to the api.
    def write(trace)
      @trace_buffer.push(trace)
    end

    # stats returns a dictionary of stats about the writer.
    def stats
      {
        traces_flushed: @traces_flushed,
        traces_buffered: @trace_buffer.length
      }
    end
  end

  # TraceBuffer buffers a maximum number of traces waiting to be sent to the
  # app.
  class TraceBuffer
    def initialize(max_size)
      @mutex = Mutex.new
      @traces = []
      @max_size = max_size
    end

    def push(trace)
      @mutex.synchronize do
        len = @traces.length
        if len < @max_size
          @traces << trace
        else
          @traces[rand(len)] = trace # drop a random one
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
        t = @traces
        @traces = []
        return t
      end
    end
  end
end
