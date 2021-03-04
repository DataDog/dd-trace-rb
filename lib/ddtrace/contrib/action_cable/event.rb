require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_support/notifications/event'
require 'ddtrace/contrib/action_cable/ext'

module Datadog
  module Contrib
    module ActionCable
      # Defines basic behaviors for an event.
      module Event
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for events.
        module ClassMethods
          def span_options
            { service: configuration[:service_name] }
          end

          def tracer
            -> { configuration[:tracer] }
          end

          def configuration
            Datadog.configuration[:action_cable]
          end
        end
      end

      # Defines behavior for the first event of a thread execution.
      #
      # This event is not expected to be nested with other event,
      # but to start a fresh tracing context.
      module RootContextEvent
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for events.
        module ClassMethods
          include Contrib::ActionCable::Event::ClassMethods

          def subscription(*args)
            super.tap do |subscription|
              subscription.before_trace { Contrib::Support.ensure_finished_context!(configuration[:tracer], Ext::APP) }
            end
          end
        end
      end
    end
  end
end
