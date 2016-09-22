
require 'span'
require 'local'
require 'writer'


module Datadog

  class Tracer

    attr_reader :writer

    def initialize(options={})

      # buffers and sends completed traces.
      @writer = options[:writer] || Datadog::Writer.new()

      # store thes the active thread in the current span.
      @buffer = Datadog::SpanBuffer.new()
      @spans = []
    end

    def trace(name, options={})
      span = Span.new(self, name, options)

      # set up inheritance
      parent = @buffer.get()
      span.set_parent(parent)
      @buffer.set(span)

      # now delete the called block to it
      if block_given?
        return span.trace(&Proc.new)
      else
        return span.trace()
      end
    end

    def record(span)
      @spans << span

      parent = span.parent
      @buffer.set(parent)
      if parent.nil?
        spans = @spans
        @spans = []
        self.write(spans)
      end
    end

    def write(spans)
      @writer.write(spans) unless @writer.nil?
    end

  end
end
