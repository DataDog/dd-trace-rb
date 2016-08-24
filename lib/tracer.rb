
require 'span'


module Datadog

  class Tracer

    attr_reader :writer

    def initialize(options={})
      @writer = options[:writer]
    end

    def span(name)
      return Span.new(self, name)
    end

    def trace(name)
      span = self.span(name)

      # now delete the called block to it
      return span.trace(&Proc.new)
    end

    def record(span)
      self.write(span)
    end

    def write(span)
      if !@writer.nil?
        @writer.write(span)
      end
    end

  end

end
