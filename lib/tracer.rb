
require 'span'
require 'local'


module Datadog

  class Tracer

    attr_reader :writer

    def initialize(options={})
      @writer = options[:writer]
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
      if !@writer.nil?
        @writer.write(spans)
      end
    end

  end

end
