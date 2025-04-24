module Datadog
  module Core
    module Errortracking
      SPAN_EVENTS_LIMIT = 100

      class Collector
        @after_stop = proc do |span_op, error|
          collector = span_op.collector
          collector.on_error(span_op, error) unless error.nil?
          span_events = collector._get_span_events
          if span_events
            span_op.span_events.concat(span_events)
            collector._clear_span_events
          end
        end

        class << self
          attr_reader :after_stop
        end

        def initialize
          @storage = {}
        end

        def add_span_event(span_op, error, span_event)
          if @storage.empty?
            events = span_op.send(:events)
            events.after_stop.subscribe(&self.class.after_stop)
          end
          @storage[error] = span_event if !@storage.key?(error) || @storage.size? >= SPAN_EVENTS_LIMIT
        end

        def _get_span_events
          @storage.values
        end

        def _clear_span_events
          @storage.clear
        end

        if RUBY_VERSION >= '3.3'
          def on_error(_span_op, error)
            @storage.delete(error)
          end
        else
          def on_error(span_op, error)
            return unless @storage.key?(error)

            if span_op.parent_id != 0
              parent = span_op.send(:parent)
              add_span_event(parent, error, @storage[error])
            end

            @storage.delete(error)
          end
        end
      end
    end
  end
end
