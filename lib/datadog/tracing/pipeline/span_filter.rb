# typed: true

require 'datadog/tracing/pipeline/span_processor'

module Datadog
  module Tracing
    module Pipeline
      # SpanFilter implements a processor that filters entire span subtrees.
      # This processor executes the configured `operation` for each {Datadog::Tracing::Span}
      # in a {Datadog::Tracing::TraceSegment}.
      #
      # When a span is filtered out, all its children spans are also removed from the trace.
      # This is required to avoid having orphan spans that do not connect to other spans
      # in the trace.
      #
      # If `operation` returns a truthy value for a span, that span is kept,
      # otherwise the span is removed from the trace.
      #
      # @public_api
      class SpanFilter < SpanProcessor
        # NOTE: this SpanFilter implementation only handles traces in which child spans appear
        # after parent spans in the trace array. If in the future child spans can be before
        # parent spans, then the code below will need to be updated.
        # @!visibility private
        def call(trace)
          spans = trace.spans
          spans.each do |span|
            next unless drop_it?(span)

            remove_children!(spans, span.id) # Modifies `spans`

            # Because {#remove_children!} could have changed the indexes
            # of `spans`, we can't simply remove `span` from its original place.
            # This prevents us from using most of the element removal
            # methods in the Array API.
            #
            # Instead, we have to find `span` again in `spans` and remove it.
            #
            # We use `delete_at` instead of `delete` as `delete` will
            # scan the whole array looking for all object equality matches.
            # We don't need to scan the whole array, only the first occurrence of
            # `span` is enough. If there are multiple instances of `span` in the
            # array, we'll eventually check it in this loop iteration, but that
            # shouldn't be possible as such a trace with duplicate spans
            # wouldn't be valid.
            spans.delete_at(spans.index(span))
          end

          trace
        end

        private

        def drop_it?(span)
          @operation.call(span) rescue false
        end

        # Removes a span subtree, starting with spans
        # that is a children of parent_span_id.
        # This method modifies the provided Array of spans.
        def remove_children!(spans, parent_span_id)
          spans.each do |span|
            if span.parent_id == parent_span_id
              remove_children!(spans, span.id)
              spans.delete_at(spans.index(span))
            end
          end
        end
      end
    end
  end
end
