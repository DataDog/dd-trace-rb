require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_support/notifications/event'
require 'ddtrace/contrib/kafka/ext'

module Datadog
  module Contrib
    module Kafka
      # Defines basic behaviors for an ActiveSupport event.
      module Event
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for Kafka events.
        module ClassMethods
          def event_name
            self::EVENT_NAME
          end

          def span_options
            { service: configuration[:service_name] }
          end

          def tracer
            -> { configuration[:tracer] }
          end

          def configuration
            Datadog.configuration[:kafka]
          end

          def process(span, _event, _id, payload)
            span.service = configuration[:service_name]
            span.set_tag(Ext::TAG_CLIENT, payload[:client_id])

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            report_if_exception(span, payload)
          end
        end
      end
    end
  end
end
