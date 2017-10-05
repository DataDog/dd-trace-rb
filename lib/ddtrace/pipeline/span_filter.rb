module Datadog
  module Pipeline
    # SpanFilter implements a processor that filters entire span subtrees
    class SpanFilter
      def initialize(filter = nil, &block)
        callable = filter || block

        raise(ArgumentError) unless callable.respond_to?(:call)

        @criteria = filter || block
      end

      def call(trace)
        black_list = trace.select(&method(:drop_it?))

        clean_trace(black_list, trace) while black_list.any?

        trace
      end

      private

      def drop_it?(span)
        @criteria.call(span) rescue false
      end

      def clean_trace(black_list, trace)
        current = black_list.shift

        trace.delete(current)

        trace.each do |span|
          black_list << span if span.parent == current
        end
      end
    end
  end
end
