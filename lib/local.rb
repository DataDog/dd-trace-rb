

require 'thread'

module Datadog

  class SpanBuffer

    def set(span)
      Thread.current[:datadog_span] = span
    end

    def get()
      return Thread.current[:datadog_span]
    end

    def pop()
      s = self.get()
      self.set(nil)
      return s
    end

  end

end
