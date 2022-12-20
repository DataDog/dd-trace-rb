require_relative '../../metadata/ext'
require_relative 'ext'
require_relative '../analytics'

module Datadog
  module Tracing
    module Contrib
      module Roda
        # Instrumentation for Roda
        module Instrumentation

          def _roda_handle_main_route
            instrument do
              super
            rescue => e
              ['500'] # [status, headers, body]
            end
          end

          def call
            instrument do
              super
            rescue => e
              ['500'] # [status, headers, body]
            end
          end

          private

          def instrument(&block)
            set_distributed_tracing_context!(request.env)

            Tracing.trace(Ext::SPAN_REQUEST) do |span|
              request_method = request.request_method.to_s.upcase

              span.service = configuration[:service_name]
              span.span_type = Tracing::Metadata::Ext::HTTP::TYPE_INBOUND

              # Using the http method as a resource, since the URL/path can trigger
              # a possibly infinite number of resources.
              span.resource = request_method

              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, request.path)
              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, request_method)

              # Add analytics tag to the span
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            response = yield

            status_code = response[0]

            # Adds status code to the resource name once the resource comes back
            span.resource = "#{request_method} #{status_code}"
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, status_code)
            span.status = 1 if status_code.to_s.start_with?('5')
            response
          end

          def configuration
            Datadog.configuration.tracing[:roda]
          end

          def set_distributed_tracing_context!(env)
            if configuration[:distributed_tracing]
              trace_digest = Tracing::Propagation::HTTP.extract(env)
              Tracing.continue_trace!(trace_digest)
            end
          end
        end
      end
    end
  end
end
