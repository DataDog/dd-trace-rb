require 'ddtrace/contrib/sinatra/env'
require 'ddtrace/contrib/sinatra/headers'

module Datadog
  module Contrib
    module Sinatra
      # Middleware used for automatically tagging configured headers and handle request span
      class TracerMiddleware
        REQUEST_TRACE_NAME = 'sinatra.request'.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          # Set the trace context (e.g. distributed tracing)
          if configuration[:distributed_tracing] && tracer.provider.context.trace_id.nil?
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          # Begin the trace
          tracer.trace(
            REQUEST_TRACE_NAME,
            service: configuration[:service_name],
            span_type: Datadog::Ext::HTTP::TYPE
          ) do |span|
            # Set the span on the Env
            Sinatra::Env.set_datadog_span(env, span)

            # Tag request headers
            Sinatra::Env.request_header_tags(env, configuration[:headers][:request]).each do |name, value|
              span.set_tag(name, value) if span.get_tag(name).nil?
            end

            # Run application stack
            status, headers, response_body = @app.call(env)

            # Tag response headers
            Sinatra::Headers.response_header_tags(headers, configuration[:headers][:response]).each do |name, value|
              span.set_tag(name, value) if span.get_tag(name).nil?
            end

            # Return response
            [status, headers, response_body]
          end
        end

        private

        def tracer
          configuration[:tracer]
        end

        def configuration
          Datadog.configuration[:sinatra]
        end

        def header_to_rack_header(name)
          "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
        end
      end
    end
  end
end
