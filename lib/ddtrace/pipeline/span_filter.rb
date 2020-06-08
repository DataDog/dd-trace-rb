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
        deleted = Set.new

        trace.delete_if do |span|
          if deleted.include?(span.parent)
            deleted << span
            true
          else
            drop = drop_it?(span)
            deleted << span if drop
            drop
          end
        end
      end

      private

      def drop_it?(span)
        @criteria.call(span) rescue false
      end
    end
  end
end
