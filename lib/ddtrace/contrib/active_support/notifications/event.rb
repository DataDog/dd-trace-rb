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
            DEFAULT_TRACER = -> { Datadog.tracer }

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
              DEFAULT_TRACER
            end
          end
        end
      end
    end
  end
end
