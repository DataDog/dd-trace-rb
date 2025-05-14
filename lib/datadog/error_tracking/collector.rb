# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module ErrorTracking
    # The Collector is in charge, for a SpanOperation of storing the span events
    # created when an error is handled. Each SpanOperation has a Collector as soon
    # as a span event is created and the Collector has the same life time as the SpanOp.
    #
    # If an error is handled then rethrown, the SpanEvent corresponding to the error
    # will be deleted. That is why we do not add directly the SpanEvent to the SpanOp.
    #
    # @api private
    class Collector
      SPAN_EVENTS_LIMIT = 100
      LOCK = Mutex.new
      # Proc called when the span_operation :after_stop event is published
      def self.after_stop
        @after_stop ||= proc do |span_op, error|
          collector = span_op.collector
          # if an error exited the scope of the span, we delete the corresponding SpanEvent.
          collector.on_error(span_op, error) unless error.nil?

          span_events = collector.get_span_events
          span_op.span_events.concat(span_events) if span_events
        end
      end

      def initialize
        @span_event_per_error = {}
      end

      def add_span_event(span_op, error, span_event)
        # When this is the first time we add a span event for a span,
        # we suscribe to the :after_stop event
        if @span_event_per_error.empty?
          events = span_op.send(:events)
          events.after_stop.subscribe(&self.class.after_stop)

          # This tag is used by the Error Tracking product to report
          # the error in Error Tracking
          span_op.set_tag(Ext::SPAN_EVENTS_HAS_EXCEPTION, true)
        end
        # Set a limit to the number of span event we can store per SpanOp
        if @span_event_per_error.key?(error) || @span_event_per_error.length < SPAN_EVENTS_LIMIT
          @span_event_per_error[error] =
            span_event
        end
      end

      if RUBY_VERSION >= '3.3'
        # Starting from ruby3.3, as we are listening to :rescue event,
        # we just want to remove the span event if the error was
        # previously handled
        def on_error(_span_op, error)
          @span_event_per_error.delete(error)
        end
      else
        # Up to ruby3.2, we are listening to :raise event. We need to ensure
        # that an error exiting the scope of a span is not handled in a parent span.
        # This function will propagate the span event to the parent span. If the
        # error is not handled in the parent span, it will be deleted by design.
        def on_error(span_op, error)
          return unless @span_event_per_error.key?(error)

          if span_op.parent?
            parent = span_op.send(:parent)
            LOCK.synchronize do
              parent_collector = parent.collector { Collector.new }
              parent_collector.add_span_event(parent, error, @span_event_per_error[error])
            end
          end

          @span_event_per_error.delete(error)
        end
      end

      def get_span_events
        @span_event_per_error.values
      end
    end
  end
end
