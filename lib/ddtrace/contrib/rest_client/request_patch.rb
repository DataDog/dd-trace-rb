require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/integration'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/rest_client/ext'

module Datadog
  module Contrib
    module RestClient
      # RestClient RequestPatch
      module RequestPatch
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def execute(&block)
            uri = URI.parse(url)

            return super(&block) unless datadog_configuration[:tracer].enabled

            datadog_trace_request(uri) do |span|
              if datadog_configuration[:distributed_tracing]
                Datadog::HTTPPropagator.inject!(span.context, processed_headers)
              end

              super(&block)
            end
          end

          def datadog_tag_request(uri, span)
            span.resource = method.to_s.upcase

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, method.to_s.upcase)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
          end

          def datadog_trace_request(uri)
            span = datadog_configuration[:tracer].trace(Ext::SPAN_REQUEST,
                                                        service: datadog_configuration[:service_name],
                                                        span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND)

            datadog_tag_request(uri, span)

            yield(span).tap do |response|
              # Verify return value is a response
              # If so, add additional tags.
              if response.is_a?(::RestClient::Response)
                span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)
              end
            end
          rescue ::RestClient::ExceptionWithResponse => e
            span.set_error(e) if Datadog::Ext::HTTP::ERROR_RANGE.cover?(e.http_code)
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, e.http_code)

            raise e
            # rubocop:disable Lint/RescueException
          rescue Exception => e
            # rubocop:enable Lint/RescueException
            span.set_error(e) if span

            raise e
          ensure
            span.finish if span
          end

          private

          def datadog_configuration
            Datadog.configuration[:rest_client]
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
end
