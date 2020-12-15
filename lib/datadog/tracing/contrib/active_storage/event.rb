require 'datadog/tracing/contrib/active_support/notifications/event'

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        # Defines basic behaviors for an ActiveStorage event.
        module Event
          def self.included(base)
            base.send(:include, ActiveSupport::Notifications::Event)
            base.send(:extend, ClassMethods)
          end

          # Class methods for ActiveStorage events.
          module ClassMethods
            def span_options
              { service: configuration[:service_name] }
            end

            def tracer
              -> { configuration[:tracer] }
            end

            def configuration
              Datadog.configuration[:active_storage]
            end
          end
        end
      end
    end
  end
end
