require 'thread'

module Datadog
  # Buffer used to store active spans
  # TODO[manu]: if this buffer remains a simple wrapper,
  # provide only an helper and use Thread.current directly
  class SpanBuffer
    # ensure that a new SpanBuffer clears the thread spans
    # TODO[manu]: be defensive and sure that users cannot "play" with buffers;
    # this issue is related to exporting the :buffer attribute in the Span model
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
end
