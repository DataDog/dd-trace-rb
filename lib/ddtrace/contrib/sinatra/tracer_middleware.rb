require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/sinatra/ext'
require 'ddtrace/contrib/sinatra/env'
require 'ddtrace/contrib/sinatra/headers'

module Datadog
  module Contrib
    module Sinatra
      # Middleware used for automatically tagging configured headers and handle request span
      class TracerMiddleware
        def initialize(app, opt = {})
          @app = app
          @app_instance = opt[:app_instance]
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def call(env)
          # Set the trace context (e.g. distributed tracing)
          if configuration[:distributed_tracing] && tracer.provider.context.trace_id.nil?
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          tracer.trace(
            Ext::SPAN_REQUEST,
            service: configuration[:service_name],
            span_type: Datadog::Ext::HTTP::TYPE_INBOUND,
            resource: env['REQUEST_METHOD']
          ) do |span|
            begin
              Sinatra::Env.set_datadog_span(env, @app_instance, span)

              response = @app.call(env)
            ensure
              Sinatra::Env.request_header_tags(env, configuration[:headers][:request]).each do |name, value|
                span.set_tag(name, value) if span.get_tag(name).nil?
              end

              request = ::Sinatra::Request.new(env)
              span.set_tag(Datadog::Ext::HTTP::URL, request.path)
              span.set_tag(Datadog::Ext::HTTP::METHOD, request.request_method)
              if request.script_name && !request.script_name.empty?
                span.set_tag(Ext::TAG_SCRIPT_NAME, request.script_name)
              end

              span.set_tag(Ext::TAG_APP_NAME, @app_instance.settings.name)

              # TODO: This backfills the non-matching Sinatra app with a "#{method} #{path}"
              # TODO: resource name. This shouldn't be the case, as that app has never handled
              # TODO: the response with that resource.
              # TODO: We should replace this backfill code with a clear `resource` that signals
              # TODO: that this Sinatra span was *not* responsible for processing the current request.
              rack_request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
              span.resource = rack_request_span.resource if rack_request_span && rack_request_span.resource

              if response
                if (status = response[0])
                  sinatra_response = ::Sinatra::Response.new([], status) # Build object to use status code helpers

                  span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, sinatra_response.status)
                  span.set_error(env['sinatra.error']) if sinatra_response.server_error?
                end

                if (headers = response[1])
                  Sinatra::Headers.response_header_tags(headers, configuration[:headers][:response]).each do |name, value|
                    span.set_tag(name, value) if span.get_tag(name).nil?
                  end
                end
              end

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              # Measure service stats
              Contrib::Analytics.set_measured(span)
            end
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
