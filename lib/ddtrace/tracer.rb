require 'ddtrace/span'
require 'ddtrace/buffer'
require 'ddtrace/writer'

module Datadog
  # Tracer class that records and creates spans related to a
  # compositions of logical units of work.
  class Tracer
    # TODO[manu]: buffer reader must be removed later
    attr_reader :writer, :buffer

    def initialize(options = {})
      # buffers and sends completed traces.
      @writer = options.fetch(:writer, Datadog::Writer.new())

      # store thes the active thread in the current span.
      @buffer = Datadog::SpanBuffer.new()
      @spans = []
    end

    def trace(name, options = {})
      span = Span.new(self, name, options)

      # set up inheritance
      parent = @buffer.get()
      span.set_parent(parent)
      @buffer.set(span)

      # now delete the called block to it
      # TODO[manu]: this part must be refactored and merged with span.trace()
      # span.trace call is mandatory and we should return the span when it's
      # finished.
      return span.trace(&Proc.new) if block_given?
      span.trace()
      span
    end

    def record(span)
      @spans << span
      parent = span.parent
      @buffer.set(parent)

      return unless parent.nil?
      spans = @spans
      @spans = []
      write(spans)
    end

    def write(spans)
      @writer.write(spans) unless @writer.nil?
    end
  end
end
