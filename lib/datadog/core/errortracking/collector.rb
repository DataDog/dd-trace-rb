module Datadog
  module Core
    module Errortracking
      class Collector
        def initialize()
          @storage = {}
          @after_stop_block = proc do |span|
            span_id = span.id
            span_events = _get_span_events(span_id)
            if span_events
              span.span_events.concat(span_events)
              _clear_span_events(span_id)
            end
          end

          @on_error_block = proc do |span_op|
            span_op.span_events.pop
          end
        end

        def add_span_event(active_span, error, span_event)
          span_id = active_span.id

          unless @storage.has_key?(span_id)
            @storage[span_id] = {}
            active_span.events.after_stop.subscribe(&@after_stop_block)
            active_span.events.on_error.subscribe(&@on_error_block) if RUBY_VERSION < '3.3'
          end

          @storage[span_id][error] = span_event
        end

        def _get_span_events(span_id)
          @storage[span_id]&.values()
        end

        def _clear_span_events(span_id)
          @storage.delete(span_id)
        end
      end
    end
  end
end
