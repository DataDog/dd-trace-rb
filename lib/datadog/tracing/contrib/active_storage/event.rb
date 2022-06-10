# typed: true

require 'datadog/tracing/contrib/active_support/notifications/event'

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        # Defines basic behaviors for an ActiveStorage event.
        module Event
          def self.included(base)
            base.include(ActiveSupport::Notifications::Event)
            base.extend(ClassMethods)
          end

          # Class methods for ActiveStorage events.
          module ClassMethods
            def span_options
              if configuration[:service_name]
                { service: configuration[:service_name] }
              else
                {}
              end
            end

            def configuration
              Datadog.configuration.tracing[:active_storage]
            end
          end
        end
      end
    end
  end
end
