# typed: false
require 'sinatra/base'

require 'ddtrace/ext/app_types'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/http'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/utils/only_once'
require 'ddtrace/contrib/sinatra/ext'
require 'ddtrace/contrib/sinatra/tracer_middleware'
require 'ddtrace/contrib/sinatra/env'

module Datadog
  module Contrib
    module Sinatra
      # Datadog::Contrib::Sinatra::Tracer is a Sinatra extension which traces
      # requests.
      module Tracer
        def route(verb, action, *)
          # Keep track of the route name when the app is instantiated for an
          # incoming request.
          condition do
            # If the option to prepend script names is enabled, then
            # prepend the script name from the request onto the action.
            #
            # DEV: env['sinatra.route'] already exists with very similar information,
            # DEV: but doesn't account for our `resource_script_names` logic.
            #
            @datadog_route = if Datadog.configuration[:sinatra][:resource_script_names]
                               "#{request.script_name}#{action}"
                             else
                               action
                             end
          end

          super
        end

        def self.registered(app)
          app.use TracerMiddleware, app_instance: app

          app.after do
            next unless Datadog.tracer.enabled

            span = Sinatra::Env.datadog_span(env, app)

            # TODO: `route` should *only* be populated if @datadog_route is defined.
            # TODO: If @datadog_route is not defined, then this Sinatra app is not responsible
            # TODO: for handling this request.
            # TODO:
            # TODO: This change would be BREAKING for any Sinatra app (classic or modular),
            # TODO: as it affects the `resource` value for requests not handled by the Sinatra app.
            # TODO: Currently we use "#{method} #{path}" in such aces, but `path` is the raw,
            # TODO: high-cardinality HTTP path, and can contain PII.
            # TODO:
            # TODO: The value we should use as the `resource` when the Sinatra app is not
            # TODO: responsible for the request is a tricky subject.
            # TODO: The best option is a value that clearly communicates that this app did not
            # TODO: handle this request. It's important to keep in mind that an unhandled request
            # TODO: by this Sinatra app might still be handled by another Rack middleware (which can
            # TODO: be a Sinatra app itself) or it might just 404 if not handled at all.
            # TODO:
            # TODO: A possible value for `resource` could set a high level description, e.g.
            # TODO: `request.request_method`, given we don't have the response object available yet.
            route = if defined?(@datadog_route)
                      @datadog_route
                    else
                      # Fallback in case no routes have matched
                      request.path
                    end

            span.resource = "#{request.request_method} #{route}"
            span.set_tag(Ext::TAG_ROUTE_PATH, route)
          end
        end

        # Method overrides for Sinatra::Base
        module Base
          MISSING_REQUEST_SPAN_ONLY_ONCE = Datadog::Utils::OnlyOnce.new
          private_constant :MISSING_REQUEST_SPAN_ONLY_ONCE

          def render(engine, data, *)
            tracer = Datadog.tracer
            return super unless tracer.enabled

            tracer.trace(Ext::SPAN_RENDER_TEMPLATE, span_type: Datadog::Ext::HTTP::TEMPLATE) do |span|
              span.set_tag(Ext::TAG_TEMPLATE_ENGINE, engine)

              # If data is a string, it is a literal template and we don't
              # want to record it.
              span.set_tag(Ext::TAG_TEMPLATE_NAME, data) if data.is_a? Symbol

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              super
            end
          end

          # Invoked when a matching route is found.
          # This method yields directly to user code.
          def route_eval
            configuration = Datadog.configuration[:sinatra]
            tracer = Datadog.tracer
            return super unless tracer.enabled

            tracer.trace(
              Ext::SPAN_ROUTE,
              service: configuration[:service_name],
              span_type: Datadog::Ext::HTTP::TYPE_INBOUND,
              resource: "#{request.request_method} #{@datadog_route}",
            ) do |span|
              span.set_tag(Ext::TAG_APP_NAME, settings.name || settings.superclass.name)
              span.set_tag(Ext::TAG_ROUTE_PATH, @datadog_route)
              span.set_tag(Ext::TAG_SCRIPT_NAME, request.script_name) if request.script_name && !request.script_name.empty?

              rack_request_span = env[Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
              rack_request_span.resource = span.resource if rack_request_span

              sinatra_request_span =
                if self.class <= ::Sinatra::Application # Classic style (top-level) application
                  Sinatra::Env.datadog_span(env, ::Sinatra::Application)
                else
                  Sinatra::Env.datadog_span(env, self.class)
                end
              if sinatra_request_span
                sinatra_request_span.resource = span.resource
              else
                MISSING_REQUEST_SPAN_ONLY_ONCE.run do
                  Datadog.logger.warn do
                    'Sinatra integration is misconfigured, reported traces will be missing request metadata ' \
                    'such as path and HTTP status code. ' \
                    'Did you forget to add `register Datadog::Contrib::Sinatra::Tracer` to your ' \
                    '`Sinatra::Base` subclass? ' \
                    'See <https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#sinatra> for more details.'
                  end
                end
              end

              Contrib::Analytics.set_measured(span)

              super
            end
          end
        end
      end
    end
  end
end
