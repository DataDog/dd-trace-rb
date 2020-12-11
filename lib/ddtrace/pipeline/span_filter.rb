module Datadog
  module Pipeline
    # SpanFilter implements a processor that filters entire span subtrees
    class SpanFilter
      def initialize(filter = nil, &block)
        callable = filter || block

        raise(ArgumentError) unless callable.respond_to?(:call)

        @criteria = filter || block
      end

      # Note: this SpanFilter implementation only handles traces in which child spans appear
      # after parent spans in the trace array. If in the future child spans can be before
      # parent spans, then the code below will need to be updated.
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
