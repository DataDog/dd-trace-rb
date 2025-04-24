# frozen_string_literal: true

module Datadog
  module Core
    module Errortracking
      # The collector is in charge of storing the span events
      # corresponding to the handled exceptions.
      #
      # We do not add the span events directly to the span as we may
      # delete some if an exception which was handled is rethrown
      class Collector
        SPAN_EVENTS_LIMIT = 100

        # Proc called when the span_operation :after_stop event is published
        def self.after_stop
          @after_stop ||= proc do |span_op, error|
            collector = span_op.collector
            # if an error exited the scope of the span
            collector.on_error(span_op, error) unless error.nil?

            span_events = collector._get_span_events
            if span_events
              span_op.span_events.concat(span_events)
              collector._clear_span_events
            end
          end
        end

        def initialize
          @storage = {}
        end

        def add_span_event(span_op, error, span_event)
          # When this is the first time we add a span event for a span,
          # we suscribe :after_stop event
          if @storage.empty?
            events = span_op.send(:events)
            events.after_stop.subscribe(&self.class.after_stop)
          end
          @storage[error] = span_event if @storage.key?(error) || @storage.length < SPAN_EVENTS_LIMIT
        end

        if RUBY_VERSION >= '3.3'
          # Starting from ruby3.3, as we are listening to :rescue event,
          # we just want to remove the span event if the error was
          # previously handled
          def on_error(_span_op, error)
            @storage.delete(error)
          end
        else
          # Up to ruby3.2, we are listening to :raise error. We need to ensure
          # that an error exiting the scope a span is not handled in a parent span.
          # This function will propagate the span event to the parent span. If the
          # error is not handled in the parent span, it will be deleted by design.
          def on_error(span_op, error)
            return unless @storage.key?(error)

            if span_op.parent_id != 0
              parent = span_op.send(:parent)
              parent.collector.add_span_event(parent, error, @storage[error])
            end

            @storage.delete(error)
          end
        end

        def _get_span_events
          @storage.values
        end

        def _clear_span_events
          @storage.clear
        end
      end
    end
  end
end
