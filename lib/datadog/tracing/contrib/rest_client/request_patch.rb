require 'uri'

require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative 'ext'

module Datadog
  module Tracing
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

              return super(&block) unless Tracing.enabled?

              datadog_trace_request(uri) do |_span, trace|
                Tracing::Propagation::HTTP.inject!(trace, processed_headers) if datadog_configuration[:distributed_tracing]

                super(&block)
              end
            end

            def datadog_tag_request(uri, span)
              span.resource = method.to_s.upcase

              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, uri.host)

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, uri.path)
              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, method.to_s.upcase)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, uri.host)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, uri.port)
            end

            def datadog_trace_request(uri)
              span = Tracing.trace(
                Ext::SPAN_REQUEST,
                service: datadog_configuration[:split_by_domain] ? uri.host : datadog_configuration[:service_name],
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND
              )

              trace = Tracing.active_trace

              datadog_tag_request(uri, span)

              yield(span, trace).tap do |response|
                # Verify return value is a response
                # If so, add additional tags.
                if response.is_a?(::RestClient::Response)
                  span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, response.code)
                end
              end
            rescue ::RestClient::ExceptionWithResponse => e
              span.set_error(e) if Tracing::Metadata::Ext::HTTP::ERROR_RANGE.cover?(e.http_code)
              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, e.http_code)

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
              Datadog.configuration.tracing[:rest_client]
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
end
