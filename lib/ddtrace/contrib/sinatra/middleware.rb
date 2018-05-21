require 'ddtrace/utils/rack/env_span_tagger_middleware'

module Datadog
  module Contrib
    module Sinatra
      class Middleware < Datadog::Utils::Rack::EnvSpanTaggerMiddleware
        ENV_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
        TRACE_NAME = 'sinatra.request'.freeze

        def self.request_span(env)
          env[ENV_REQUEST_SPAN]
        end

        protected

        def configuration
          Datadog.configuration[:sinatra]
        end

        def build_request_span(env)
          tracer = configuration[:tracer]

          distributed_tracing = configuration[:distributed_tracing]

          if distributed_tracing && tracer.provider.context.trace_id.nil?
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          tracer.trace(TRACE_NAME,
                       service: Datadog.configuration[:sinatra][:service_name],
                       span_type: Datadog::Ext::HTTP::TYPE)
        end

        def env_request_span
          ENV_REQUEST_SPAN
        end
      end
    end
  end
end
