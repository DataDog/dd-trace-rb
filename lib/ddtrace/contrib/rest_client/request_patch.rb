# typed: false
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/metadata'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/rest_client/ext'

module Datadog
  module Contrib
    module RestClient
      # RestClient RequestPatch
      module RequestPatch
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def execute(&block)
            uri = URI.parse(url)

            return super(&block) unless Datadog::Tracing.enabled?

            datadog_trace_request(uri) do |_span, trace|
              Datadog::HTTPPropagator.inject!(trace, processed_headers) if datadog_configuration[:distributed_tracing]

              super(&block)
            end
          end

          def datadog_tag_request(uri, span)
            span.resource = method.to_s.upcase

            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, uri.host)

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, method.to_s.upcase)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
          end

          def datadog_trace_request(uri)
            span = Datadog::Tracing.trace(
              Ext::SPAN_REQUEST,
              service: datadog_configuration[:service_name],
              span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND
            )

            trace = Datadog::Tracing.active_trace

            datadog_tag_request(uri, span)

            yield(span, trace).tap do |response|
              # Verify return value is a response
              # If so, add additional tags.
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code) if response.is_a?(::RestClient::Response)
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
            Datadog::Tracing.configuration[:rest_client]
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
