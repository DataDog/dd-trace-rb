require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'

module Datadog
  module Contrib
    module Httprb
      class DatadogWrap

        def initialize(opts = {})
          @opts = opts
        end

        def wrap_request(request)
          begin
            if tracer_enabled?
              datadog_span = datadog_configuration[:tracer].trace(
                Ext::SPAN_REQUEST,
                service: datadog_configuration[:service_name],
                span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND
              )

              Datadog::HTTPPropagator.inject!(datadog_span.context, request.headers) if request.headers
              Contrib::Analytics.set_sample_rate(datadog_span, analytics_sample_rate) if analytics_enabled?

              if request.verb && request.verb.is_a?(String)
                http_method = request.verb.to_s.upcase
                datadog_span.resource = http_method
              else
                log.debug("span #{Ext::SPAN_REQUEST} missing request verb, no resource set")
              end          

              if request.uri
                uri = request.uri
                datadog_span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
                datadog_span.set_tag(Datadog::Ext::HTTP::METHOD, http_method)
                datadog_span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
                datadog_span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
              else
                log.debug("service #{datadog_configuration[:service_name]} span #{Ext::SPAN_REQUEST} missing uri, no uri metadata set")
              end
            end
          rescue StandardError => e
            log.error(e.message)
          ensure
            return request
          end
        end

        def wrap_response(response)          
          begin
            if tracer_enabled?

              tracer = datadog_configuration[:tracer]
              datadog_span = tracer.active_span

              response_status = response.try(:status)

              if response_status
                datadog_span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response_status)
              end

              if Datadog::Ext::HTTP::ERROR_RANGE.cover?(response_status)
                datadog_span.status = Datadog::Ext::Errors::STATUS

                message = response.try(:reason)

                if message
                  datadog_span.set_tag(Datadog::Ext::Errors::MSG, message)
                else
                  datadog_span.set_tag(Datadog::Ext::Errors::MSG, "Request has failed: #{200}")
                end
              end
            end
          rescue StandardError => e
            log.error(e.message)            
          ensure
            if datadog_configuration[:tracer] && datadog_configuration[:tracer].active_span
              datadog_configuration[:tracer].active_span.finish unless datadog_configuration[:tracer].active_span.finished?
            end

            return response
          end
        end

        def on_error(request, error); end

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