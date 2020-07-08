require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/sinatra/ext'
require 'ddtrace/contrib/sinatra/env'
require 'ddtrace/contrib/sinatra/headers'

module Datadog
  module Contrib
    module Sinatra
      # Middleware used for automatically tagging configured headers and handle request span
      class TracerMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          # Set the trace context (e.g. distributed tracing)
          if configuration[:distributed_tracing] && tracer.provider.context.trace_id.nil?
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          Sinatra::Env.set_middleware_start_time(env)

          # Run application stack
          response = @app.call(env)
        ensure
          # Augment current Sinatra middleware span if we are the top-most Sinatra app on the Rack stack.
          span = Sinatra::Env.datadog_span(env)
          if span
            Sinatra::Env.request_header_tags(env, configuration[:headers][:request]).each do |name, value|
              span.set_tag(name, value) if span.get_tag(name).nil?
            end

            if response && (headers = response[1])
              Sinatra::Headers.response_header_tags(headers, configuration[:headers][:response]).each do |name, value|
                span.set_tag(name, value) if span.get_tag(name).nil?
              end
            end

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            span.finish

            # Remove span from env, so other Sinatra apps mounted on this same
            # Rack stack do not modify it with their own information.
            Sinatra::Env.set_datadog_span(env, nil)
          end
        end

        private

        def tracer
          configuration[:tracer]
        end

        def analytics_enabled?
          Contrib::Analytics.enabled?(configuration[:analytics_enabled])
        end

        def analytics_sample_rate
          configuration[:analytics_sample_rate]
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
