# typed: true
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_support/notifications/event'
require 'ddtrace/contrib/action_cable/ext'

module Datadog
  module Contrib
    module ActionCable
      # Defines basic behaviors for an event.
      module Event
        def self.included(base)
          base.include(ActiveSupport::Notifications::Event)
          base.extend(ClassMethods)
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
          base.include(ActiveSupport::Notifications::Event)
          base.extend(ClassMethods)
        end

        # Class methods for events.
        module ClassMethods
          include Contrib::ActionCable::Event::ClassMethods

          def subscription(*args)
            super.tap do |subscription|
              subscription.before_trace { ensure_clean_context! }
            end
          end

          private

          # Context objects are thread-bound.
          # If an integration re-uses threads, context from a previous trace
          # could leak into the new trace. This "cleans" current context,
          # preventing such a leak.
          def ensure_clean_context!
            return unless configuration[:tracer].active_span

            configuration[:tracer].provider.context = Context.new
          end
        end
      end
    end
  end
end
