# typed: false
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
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
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
            # this is kept nil until we set a correct one (either in the route or with a fallback in the ensure below)
            # the nil signals that there's no good one yet and is also seen by profiler, when sampling the resource
            resource: nil,
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
              span.set_tag(Ext::TAG_SCRIPT_NAME, request.script_name) if request.script_name && !request.script_name.empty?

              span.set_tag(Ext::TAG_APP_NAME, @app_instance.settings.name)

              # If this app handled the request, then Contrib::Sinatra::Tracer OR Contrib::Sinatra::Base set the
              # resource; if no resource was set, let's use a fallback
              span.resource = env['REQUEST_METHOD'] if span.resource.nil?

              rack_request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
              if rack_request_span
                if rack_request_span.resource
                  # TODO: This backfills the non-matching Sinatra app with a "#{method} #{path}"
                  # TODO: resource name. This shouldn't be the case, as that app has never handled
                  # TODO: the response with that resource.
                  # TODO: We should replace this backfill code with a clear `resource` that signals
                  # TODO: that this Sinatra span was *not* responsible for processing the current request.
                  span.resource = rack_request_span.resource
                else
                  # This propagates the Sinatra resource to the Rack span,
                  # since the latter is unaware of what the resource might be
                  # and would fallback to a generic resource name when unset
                  rack_request_span.resource = span.resource
                end
              end

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
