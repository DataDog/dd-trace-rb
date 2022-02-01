# typed: false
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/active_support/notifications/event'
require 'datadog/tracing/contrib/action_mailer/ext'

module Datadog
  module Tracing
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
              options = {}
              options[:service] = configuration[:service_name] if configuration[:service_name]
              options
            end

            def configuration
              Tracing.configuration[:action_mailer]
            end

            def process(span, event, _id, payload)
              span.service = configuration[:service_name] if configuration[:service_name]
              span.resource = payload[:mailer]
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)

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
end
