require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/rest_client/ext'

module Datadog
  module Contrib
    module HTTParty
      module Instrumentation
        # HTTParty Request
        module Request
          def self.included(base)
            base.send(:prepend, InstanceMethods)
          end

          # InstanceMethods - implementing instrumentation
          module InstanceMethods
            def uri
              # uri is a method not a property in underlying class
              # cache it so that it is only called once per call to 'perform', and then delete it
              @dd_uri ||= super
            end

            def method
              http_method::METHOD
            end

            def perform(&block)
              return super unless tracer.enabled

              tracer.trace(Ext::SPAN_REQUEST, on_error: proc { |span, e| handle_error(span, e) }) do |span|
                annotate_span!(span)

                super.tap do |response|
                  if span && response.respond_to?(:code)
                    span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)
                  end
                end
              end
            ensure
              # delete cached uri
              remove_instance_variable('@dd_uri') if instance_variable_defined?('@dd_uri')
            end

            private

            def handle_error(span, e)
              return if span.nil?

              if e.is_a?(::HTTParty::ResponseError)
                code = e.response.code.to_i
                span.set_error(e) if Datadog::Ext::HTTP::ERROR_RANGE.cover?(code)
                span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, code)
              else
                span.set_error(e)
              end
            end

            def annotate_span!(span)
              return if span.nil?

              # add tags to span
              span.resource = method
              span.service = service_name
              span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND
              span.set_tag(Datadog::Ext::HTTP::METHOD, method.to_s.upcase)
              span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              if distributed_tracing?
                # add span context to http headers
                headers = options[:headers].respond_to?(:to_hash) ? options[:headers].to_hash : {}
                Datadog::HTTPPropagator.inject!(span.context, headers)
                options[:headers] = headers
              end
            end

            def datadog_pin
              return nil unless options[Helpers::DATADOG_TRACER_OPTIONS_KEY]
              @datadog_pin ||= begin
                service_name = options[Helpers::DATADOG_TRACER_OPTIONS_KEY][:service_name] ||
                               datadog_configuration[:service_name]
                tracer = options[Helpers::DATADOG_TRACER_OPTIONS_KEY][:tracer] || datadog_configuration[:tracer]
                Datadog::Pin.new(
                  service_name,
                  app: Ext::APP,
                  app_type: Datadog::Ext::AppTypes::WEB,
                  tracer: tracer
                )
              end
            end

            def datadog_configuration
              Datadog.configuration[:httparty]
            end

            def tracer
              (datadog_pin && datadog_pin.tracer) || datadog_configuration[:tracer]
            end

            def service_name
              (datadog_pin && datadog_pin.service_name) || datadog_configuration[:service_name]
            end

            def analytics_enabled?
              Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
            end

            def analytics_sample_rate
              datadog_configuration[:analytics_sample_rate]
            end

            def distributed_tracing?
              datadog_configuration[:distributed_tracing]
            end
          end
        end
      end
    end
  end
end
