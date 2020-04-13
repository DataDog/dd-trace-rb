require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'
require 'ddtrace/propagation/http_propagator'

module Datadog
  module Contrib
    module Httprb
      # Instrumentation for Httprb
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # Instance methods for configuration
        module InstanceMethods
          def perform(req, options)
            pin = datadog_pin

            return super(req, options) unless pin && pin.tracer

            pin.tracer.trace(Ext::SPAN_REQUEST, on_error: method(:annotate_span_with_error!)) do |span|
              begin
                span.service = pin.service
                span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND

                if pin.tracer.enabled && !should_skip_distributed_tracing?(pin)
                  Datadog::HTTPPropagator.inject!(span.context, req)
                end

                # Add additional request specific tags to the span.
                annotate_span_with_request!(span, req)
              rescue StandardError => e
                logger.error("error preparing span for http.rb request: #{e}, Soure: #{e.backtrace}")
              ensure
                res = super(req, options)
              end

              # Add additional response specific tags to the span.
              annotate_span_with_response!(span, res)

              res
            end
          end

          private

          def annotate_span_with_request!(span, req)
            if req.verb && req.verb.is_a?(String) || req.verb.is_a?(Symbol)
              http_method = req.verb.to_s.upcase
              span.resource = http_method
              span.set_tag(Datadog::Ext::HTTP::METHOD, http_method)
            else
              logger.debug("span #{Ext::SPAN_REQUEST} missing request verb, no resource set")
            end

            if req.uri
              uri = req.uri
              span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
            else
              logger.debug("service #{datadog_configuration[:service_name]} span #{Ext::SPAN_REQUEST} missing uri")
            end

            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
          end

          def annotate_span_with_response!(span, response)
            return unless response && response.code

            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)

            case response.code.to_i
            when 400...599
              begin
                message = JSON.parse(response.body)['message']
              rescue
                message = 'Error'
              end
              span.set_error(["Error #{response.code}", message])
            end
          end

          def annotate_span_with_error!(span, error)
            span.set_error(error)
          end

          def datadog_pin
            @datadog_pin ||= begin
              service = datadog_configuration[:service_name]
              tracer = Datadog.configuration[:httprb][:tracer]

              Datadog::Pin.new(service, app: Ext::APP, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
            end
          end

          def tracer
            datadog_configuration[:tracer]
          end

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

          def logger
            Datadog.logger
          end

          def should_skip_distributed_tracing?(pin)
            if pin.config && pin.config.key?(:distributed_tracing)
              return !pin.config[:distributed_tracing]
            end

            !datadog_configuration[:distributed_tracing]
          end
        end
      end
    end
  end
end
