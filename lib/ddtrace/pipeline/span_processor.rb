module Datadog
  module Pipeline
    # SpanProcessor
    class SpanProcessor
      def initialize(operation = nil, &block)
        callable = operation || block

        raise(ArgumentError) unless callable.respond_to?(:call)

        @operation = operation || block
      end

      def call(trace)
        trace.each do |span|
          @operation.call(span) rescue next
        end
      end
    end
  end
end
