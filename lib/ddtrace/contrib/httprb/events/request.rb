require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/httprb/event'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'


module Datadog
  module Contrib
    module Httprb
      module Events
        # Defines instrumentation for 'perform_action.action_cable' event.
        #
        # An action, triggered by a WebSockets client, invokes a method
        # in the server's channel instance.
        module Request
          EVENT_NAME = 'request.http'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_REQUEST
          end

          def span_type
            Datadog::Ext::HTTP::TYPE_OUTBOUND
          end

          def process(span, _event, _id, payload)
            if tracer_enabled?

            response_status = payload["response"].code

            if response_status
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response_status)
            end

            if Datadog::Ext::HTTP::ERROR_RANGE.cover?(response_status)
              span.status = Datadog::Ext::Errors::STATUS

              message = payload["response"].reason

              if message
                span.set_tag(Datadog::Ext::Errors::MSG, message)
              else
                span.set_tag(Datadog::Ext::Errors::MSG, "Request has failed: #{response_status}")
              end
            end
          end

          private

          def datadog_configuration
            Datadog.configuration[:httprb]
          end

          def tracer_enabled?
            datadog_configuration[:tracer].enabled
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end

          def log
            Datadog::Tracer.log
          end
        end
      end
    end
  end
end