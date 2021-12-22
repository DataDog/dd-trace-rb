# typed: true
module Datadog
  module Pipeline
    # SpanFilter implements a processor that filters entire span subtrees
    # @public_api
    class SpanFilter
      def initialize(filter = nil, &block)
        callable = filter || block

        raise(ArgumentError) unless callable.respond_to?(:call)

        @criteria = filter || block
      end

      # NOTE: this SpanFilter implementation only handles traces in which child spans appear
      # after parent spans in the trace array. If in the future child spans can be before
      # parent spans, then the code below will need to be updated.
      # @!visibility private
      def call(trace)
        deleted = Set.new

        trace.spans.delete_if do |span|
          should_delete = deleted.include?(span.parent_id) || drop_it?(span)
          deleted << span.id if should_delete
          should_delete
        end

        trace
      end

      private

      def drop_it?(span)
        @criteria.call(span) rescue false
      end
    end
  end
end
