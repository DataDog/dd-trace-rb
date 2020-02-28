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
        module StartRequest

          EVENT_NAME = 'start_request.http'.freeze

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
              span.service = datadog_configuration[:service_name]
              span.type = Datadog::Ext::HTTP::TYPE_OUTBOUND

              Datadog::HTTPPropagator.inject!(datadog_span.context, payload["request"].headers) if payload["request"].headers
              Contrib::Analytics.set_sample_rate(datadog_span, analytics_sample_rate) if analytics_enabled?

              if payload["request"].verb && payload["request"].verb.is_a?(String) || payload["request"].verb.is_a?(Symbol)
                http_method = payload["request"].verb.to_s.upcase
                span.resource = http_method
                span.set_tag(Datadog::Ext::HTTP::METHOD, http_method)
              else
                log.debug("span #{Ext::SPAN_REQUEST} missing request verb, no resource set")
              end

              if payload["request"].uri
                uri = payload["request"].uri
                span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
                span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
                span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
              else
                log.debug("service #{datadog_configuration[:service_name]} span #{Ext::SPAN_REQUEST} missing uri")
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