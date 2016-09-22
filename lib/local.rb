

require 'thread'

module Datadog

  class SpanBuffer

    # Set the current active span.
    def set(span)
      Thread.current[:datadog_span] = span
    end

    # Return the current active span or nil.
    def get()
      return Thread.current[:datadog_span]
    end

    # Pop the current active span.
    def pop()
      s = self.get()
      self.set(nil)
      return s
    end

  end

end
