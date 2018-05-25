module Datadog
  module Contrib
    module Sinatra
      # Middleware used for automatically tagging configured headers and handle request span
      module RequestSpan
        SINATRA_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
        SINATRA_REQUEST_TRACE_NAME = 'sinatra.request'.freeze

        module_function

        def span!(env)
          env[SINATRA_REQUEST_SPAN] ||= build_span(env)
        end

        def build_span(env)
          tracer = configuration[:tracer]
          distributed_tracing = configuration[:distributed_tracing]

          if distributed_tracing && tracer.provider.context.trace_id.nil?
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          tracer.trace(SINATRA_REQUEST_TRACE_NAME,
                       service: configuration[:service_name],
                       span_type: Datadog::Ext::HTTP::TYPE)
        end

        def configuration
          Datadog.configuration[:sinatra]
        end
      end
    end
  end
end
