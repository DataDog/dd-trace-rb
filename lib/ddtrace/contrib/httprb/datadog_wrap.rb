
require 'uri'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'
require 'ddtrace/propagation/http_propagator'

require 'http'

module Datadog
  module Contrib
    module Httprb
      class DatadogWrap < ::HTTP::Feature

        def initialize(*)
          super
        end

        def wrap_request(request)
          begin
            return super(request) unless tracer_enabled?

            datadog_span = datadog_configuration[:tracer].trace(
              Ext::SPAN_REQUEST,
              service: datadog_configuration[:service_name],
              span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND
            )
            
            if request && request.headers
              Datadog::HTTPPropagator.inject!(datadog_span.context, request.headers)
            end

            Contrib::Analytics.set_sample_rate(datadog_span, analytics_sample_rate) if analytics_enabled?

            http_method = request.try(:verb).try(:to_s).try(:upcase)

            datadog_span.resource = http_method  

            if request.try(:uri)
              uri = request.uri
              datadog_span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
              datadog_span.set_tag(Datadog::Ext::HTTP::METHOD, http_method)
              datadog_span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
              datadog_span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
            end

            return request
          ensure
            return request
          end
        end

        def wrap_response(response)
          begin
            return super(request) unless tracer_enabled?

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

            datadog_span.finish

            return response
          ensure
            datadog_configuration[:tracer].active_span.finish
            return response
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
      end
    end
  end
end