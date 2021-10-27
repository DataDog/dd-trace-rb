# typed: false
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_support/notifications/event'
require 'ddtrace/contrib/action_mailer/ext'

module Datadog
  module Contrib
    module ActionMailer
      # Defines basic behaviors for an ActionMailer event.
      module Event
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for ActionMailer events.
        module ClassMethods
          def span_options
            { service: configuration[:service_name] }
          end

          def tracer
            Datadog.tracer
          end

          def configuration
            Datadog.configuration[:action_mailer]
          end

          def process(span, event, _id, payload)
            span.service = configuration[:service_name]
            span.resource = payload[:mailer]

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            report_if_exception(span, payload)
          rescue StandardError => e
            Datadog.logger.debug(e.message)
          end
        end
      end
    end
  end
end
