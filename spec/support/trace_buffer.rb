require 'monitor'

# FauxWriter is a dummy writer that buffers spans locally.
class TestTraceBuffer
  def initialize
    @mutex = Monitor.new
    @spans = []
  end

  # Pushes a trace onto the buffer
  def <<(trace)
    @mutex.synchronize do
      @spans << trace
    end
  end

  alias_method :push, :<<

  # Returns all accumulated traces,
  # without flushing the buffer.
  def spans
    @mutex.synchronize do
      sort_spans!(@spans)
    end
  end

  # Returns all accumulated traces,
  # and flushes the buffer.
  def spans!
    @mutex.synchronize do
      result = spans
      clear!
      result
    end
  end

  # Empties the buffer
  def clear!
    @mutex.synchronize do
      @spans = []
    end
  end

  def trace0_spans
    @mutex.synchronize do
      return [] unless @spans
      return [] if @spans.empty?

      spans = @spans[0]
      @spans = @spans[1..@spans.size]
      spans
    end
  end

  def sort_spans!(spans)
    spans.flatten.sort! do |a, b|
      if a.name == b.name
        if a.resource == b.resource
          if a.start_time == b.start_time
            a.end_time <=> b.end_time
          else
            a.start_time <=> b.start_time
          end
        else
          a.resource <=> b.resource
        end
      else
        a.name <=> b.name
      end
    end
  end
end
