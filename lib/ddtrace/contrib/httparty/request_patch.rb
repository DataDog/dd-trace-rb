require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/rest_client/ext'

module Datadog
  module Contrib
    module HTTParty
      # HTTParty RequestPatch
      module RequestPatch
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

          def perform(&block)
            return super(&block) unless tracer.enabled

            method = http_method::METHOD
            datadog_trace_request(method, uri) do |span|
              if distributed_tracing?
                headers = options[:headers].respond_to?(:to_hash) ? options[:headers].to_hash : {}
                Datadog::HTTPPropagator.inject!(span.context, headers)
                options[:headers] = headers
              end

              super(&block)
            end
          ensure
            # delete cached uri
            remove_instance_variable('@dd_uri') if instance_variable_defined?('@dd_uri')
          end

          def datadog_tag_request(method, uri, span)
            span.resource = method.to_s.upcase

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, method.to_s.upcase)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
          end

          def datadog_trace_request(method, uri)
            span = tracer.trace(Ext::SPAN_REQUEST,
                                service: service_name,
                                span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND)

            datadog_tag_request(method, uri, span)

            yield(span).tap do |response|
              # Verify return value is a response
              # If so, add additional tags.
              if response.is_a?(::HTTParty::Response)
                span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)
              end
            end
          rescue ::HTTParty::ResponseError => e
            code = e.response.code.to_i
            span.set_error(e) if Datadog::Ext::HTTP::ERROR_RANGE.cover?(code)
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, code)

            raise e
            # rubocop:disable Lint/RescueException
          rescue Exception => e
            # rubocop:enable Lint/RescueException
            span.set_error(e)

            raise e
          ensure
            span.finish
          end

          private

          def datadog_pin
            return nil unless options[:dd_options]
            @datadog_pin ||= begin
              service_name = options[:dd_options][:service_name] || datadog_configuration[:service_name]
              tracer = options[:dd_options][:tracer] || datadog_configuration[:tracer]
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
