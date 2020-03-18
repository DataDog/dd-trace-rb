require 'ddtrace/contrib/active_support/notifications/subscriber'

module Datadog
  module Contrib
    module ActiveSupport
      module Notifications
        # Defines behaviors for an ActiveSupport::Notifications event.
        # Compose this into a module or class, then define
        # #event_name, #span_name, and #process. You can then
        # invoke Event.subscribe! to more easily subscribe to an event.
        module Event
          def self.included(base)
            base.send(:include, Subscriber)
            base.send(:extend, ClassMethods)
            base.send(:on_subscribe) { base.subscribe }
          end

          # Redefines some class behaviors for a Subscriber to make
          # it a bit simpler for an Event.
          module ClassMethods
            def subscribe!
              super
            end

            def subscription(span_name = nil, options = nil, tracer = nil)
              super(
                span_name || self.span_name,
                options || span_options,
                tracer || self.tracer,
                &method(:process)
              )
            end

            def subscribe(pattern = nil, span_name = nil, options = nil, tracer = nil)
              if supported?
                super(
                  pattern || event_name,
                  span_name || self.span_name,
                  options || span_options,
                  tracer || self.tracer,
                  &method(:process)
                )
              end
            end

            def supported?
              true
            end

            def span_options
              {}
            end

            def tracer
              Datadog.tracer
            end
          end
        end

        # Extension to {Event} class that ensures the current {Context}
        # is always clean when the event is processed.
        #
        # This is a safeguard as Contexts are thread-bound.
        # If an integration re-uses threads, the context from a previous
        # execution could leak into the new execution.
        #
        # This module *cannot* be used for events can be nested, as
        # it drops all spans currently active in the {Context}.
        module RootEvent
          def subscription(*args)
            super.tap do |subscription|
              subscription.before_trace { ensure_clean_context! }
            end
          end

          private

          # Clears context if there are unfinished spans in it
          def ensure_clean_context!
            unfinished_span = configuration[:tracer].call_context.current_span
            return unless unfinished_span

            Diagnostics::Health.metrics.error_unfinished_context(
              1, tags: [
                "span_name:#{unfinished_span.name}",
                "event:#{self}"
              ]
            )

            configuration[:tracer].provider.context = Context.new
          end
        end
      end
    end
  end
end
