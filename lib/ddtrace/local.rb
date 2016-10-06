require 'thread'

module Datadog
  # Buffer used to store active spans
  class SpanBuffer
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
end
