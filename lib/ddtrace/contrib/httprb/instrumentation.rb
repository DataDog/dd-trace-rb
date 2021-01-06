require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/http_annotation_helper'

module Datadog
  module Contrib
    module Httprb
      # Instrumentation for Httprb
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # Instance methods for configuration
        # rubocop:disable Metrics/ModuleLength
        module InstanceMethods
          include Datadog::Contrib::HttpAnnotationHelper

          def perform(req, options)
            host = req.uri.host if req.respond_to?(:uri) && req.uri
            request_options = datadog_configuration(host)
            pin = datadog_pin(request_options)

            return super(req, options) unless pin && pin.tracer

            pin.tracer.trace(Ext::SPAN_REQUEST, on_error: method(:annotate_span_with_error!)) do |span|
              begin
                request_options[:service_name] = pin.service_name
                span.service = service_name(host, request_options)
                span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND

                if pin.tracer.enabled && !should_skip_distributed_tracing?(pin)
                  Datadog::HTTPPropagator.inject!(span.context, req)
                end

                # Add additional request specific tags to the span.
                annotate_span_with_request!(span, req, request_options)
              rescue StandardError => e
                logger.error("error preparing span for http.rb request: #{e}, Source: #{e.backtrace}")
              ensure
                res = super(req, options)
              end

              # Add additional response specific tags to the span.
              annotate_span_with_response!(span, res)

              res
            end
          end

          private

          def annotate_span_with_request!(span, req, req_options)
            if req.verb && req.verb.is_a?(String) || req.verb.is_a?(Symbol)
              http_method = req.verb.to_s.upcase
              span.resource = http_method
              span.set_tag(Datadog::Ext::HTTP::METHOD, http_method)
            else
              logger.debug("service #{req_options[:service_name]} span #{Ext::SPAN_REQUEST} missing request verb")
            end

            if req.uri
              uri = req.uri
              span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
            else
              logger.debug("service #{req_options[:service_name]} span #{Ext::SPAN_REQUEST} missing uri")
            end

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

            set_analytics_sample_rate(span, req_options)
          end

          def annotate_span_with_response!(span, response)
            return unless response && response.code

            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)

            case response.code.to_i
            when 400...599
              # https://github.com/DataDog/dd-trace-rb/issues/1116
              # parsing the response body message will alter downstream application behavior
              span.set_error(["Error #{response.code}", 'Error'])
            end
          end

          def annotate_span_with_error!(span, error)
            span.set_error(error)
          end

          def datadog_pin(config = Datadog.configuration[:httprb])
            service = config[:service_name]
            tracer = config[:tracer]

            @datadog_pin ||= begin
              Datadog::Pin.new(
                service,
                app: Ext::APP,
                app_type: Datadog::Ext::HTTP::TYPE_OUTBOUND,
                tracer: -> { config[:tracer] }
              )
            end

            if @datadog_pin.service_name == default_datadog_pin.service_name && @datadog_pin.service_name != service
              @datadog_pin.service = service
            end
            if @datadog_pin.tracer == default_datadog_pin.tracer && @datadog_pin.tracer != tracer
              @datadog_pin.tracer = tracer
            end

            @datadog_pin
          end

          def default_datadog_pin
            config = Datadog.configuration[:httprb]
            service = config[:service_name]

            @default_datadog_pin ||= begin
              Datadog::Pin.new(
                service,
                app: Ext::APP,
                app_type: Datadog::Ext::HTTP::TYPE_OUTBOUND,
                tracer: -> { config[:tracer] }
              )
            end
          end

          def datadog_configuration(host = :default)
            Datadog.configuration[:httprb, host]
          end

          def analytics_enabled?(request_options)
            Contrib::Analytics.enabled?(request_options[:analytics_enabled])
          end

          def logger
            Datadog.logger
          end

          def should_skip_distributed_tracing?(pin)
            if pin.config && pin.config.key?(:distributed_tracing)
              return !pin.config[:distributed_tracing]
            end

            !Datadog.configuration[:httprb][:distributed_tracing]
          end

          def set_analytics_sample_rate(span, request_options)
            return unless analytics_enabled?(request_options)
            Contrib::Analytics.set_sample_rate(span, request_options[:analytics_sample_rate])
          end
        end
      end
    end
  end
end
