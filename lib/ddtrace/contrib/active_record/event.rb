require 'ddtrace/contrib/active_support/notifications/event'

module Datadog
  module Contrib
    module ActiveRecord
      # Defines basic behaviors for an ActiveRecord event.
      module Event
        def self.included(base)
          base.include(ActiveSupport::Notifications::Event)
          base.extend(ClassMethods)
        end

        # Class methods for ActiveRecord events.
        module ClassMethods
          def span_options
            { service: configuration[:service_name] }
          end

          def tracer
            -> { configuration[:tracer] }
          end

          def configuration
            Datadog.configuration[:active_record]
          end
        end
      end
    end
  end
end
