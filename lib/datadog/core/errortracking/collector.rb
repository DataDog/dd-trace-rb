module Datadog
  module Core
    module Errortracking
      class Collector
        def initialize
          @storage = {}
          @before_finish_block = proc do |span|
            span_id = span.id

            span_events = _get_span_events(span_id)
            if span_events
              span.span_events.concat(span_events)
              _clear_span_events(span_id)
            end
          end

          @on_error_block = proc do |span_op, error|
            @storage[span_op.id]&.delete(error)
          end
        end

        def add_span_event(active_span, error, span_event)
          span_id = active_span.id

          unless @storage.key?(span_id)
            @storage[span_id] = {}
            events = active_span.send(:events)
            events.before_finish.subscribe(&@before_finish_block)
            events.on_error.subscribe(&@on_error_block)
          end
          @storage[span_id][error] = span_event
        end

        def _get_span_events(span_id)
          @storage[span_id]&.values
        end

        def _clear_span_events(span_id)
          @storage.delete(span_id)
        end
      end
    end
  end
end
