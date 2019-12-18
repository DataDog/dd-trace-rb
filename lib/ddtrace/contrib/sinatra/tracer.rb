require 'sinatra/base'

require 'ddtrace/ext/app_types'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/http'
require 'ddtrace/propagation/http_propagator'

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
            @datadog_route = if Datadog.configuration[:sinatra][:resource_script_names]
                               "#{request.script_name}#{action}"
                             else
                               action
                             end
          end

          super
        end

        def self.registered(app)
          ::Sinatra::Base.module_eval do
            def render(engine, data, *)
              output = ''
              tracer = Datadog.configuration[:sinatra][:tracer]
              if tracer.enabled
                tracer.trace(Ext::SPAN_RENDER_TEMPLATE, span_type: Datadog::Ext::HTTP::TEMPLATE) do |span|
                  # If data is a string, it is a literal template and we don't
                  # want to record it.
                  span.set_tag(Ext::TAG_TEMPLATE_NAME, data) if data.is_a? Symbol

                  output = super
                end
              else
                output = super
              end

              output
            end
          end

          app.use TracerMiddleware

          app.before do
            return unless Datadog.configuration[:sinatra][:tracer].enabled

            span = Sinatra::Env.datadog_span(env)
            span.set_tag(Datadog::Ext::HTTP::URL, request.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, request.request_method)
          end

          app.after do
            return unless Datadog.configuration[:sinatra][:tracer].enabled

            span = Sinatra::Env.datadog_span(env)

            unless span
              Datadog::Logger.log.error('missing request span in :after hook')
              return
            end

            span.resource = "#{request.request_method} #{@datadog_route}"
            span.set_tag(Ext::TAG_ROUTE_PATH, @datadog_route)
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.status)
            span.set_error(env['sinatra.error']) if response.server_error?
          end
        end
      end
    end
  end
end
