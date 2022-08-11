# typed: false

require 'sinatra/base'

require_relative '../../../core/utils/only_once'
require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative 'env'
require_relative 'ext'
require_relative 'tracer_middleware'

module Datadog
  module Tracing
    module Contrib
      module Sinatra
        # Datadog::Tracing::Contrib::Sinatra::Tracer is a Sinatra extension which traces
        # requests.
        module Tracer
          def self.registered(app)
            app.use TracerMiddleware, app_instance: app
          end

          # Method overrides for Sinatra::Base
          module Base
            # MISSING_REQUEST_SPAN_ONLY_ONCE = Core::Utils::OnlyOnce.new
            # private_constant :MISSING_REQUEST_SPAN_ONLY_ONCE

            def render(engine, data, *)
              return super unless Tracing.enabled?

              Tracing.trace(Ext::SPAN_RENDER_TEMPLATE, span_type: Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE) do |span|
                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_RENDER_TEMPLATE)

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
              configuration = Datadog.configuration.tracing[:sinatra]
              return super unless Tracing.enabled?

              verb, path = env['sinatra.route'].split(' ', 2)

              datadog_route = if Datadog.configuration.tracing[:sinatra][:resource_script_names]
                                # TODO: This should be the default
                                "#{verb} #{request.script_name}#{path}"
                              else
                                env['sinatra.route']
                              end

              Tracing.trace(
                Ext::SPAN_ROUTE,
                service: configuration[:service_name],
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND,
                resource: datadog_route,
              ) do |span, trace|
                span.set_tag(Ext::TAG_APP_NAME, settings.name || settings.superclass.name)

                if Datadog.configuration.tracing[:sinatra][:resource_script_names]
                  span.set_tag(Ext::TAG_ROUTE_PATH, request.path)
                else
                  span.set_tag(Ext::TAG_ROUTE_PATH, request.path_info)
                end

                if request.script_name && !request.script_name.empty?
                  span.set_tag(Ext::TAG_SCRIPT_NAME, request.script_name)
                end

                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_ROUTE)

                trace.resource = span.resource

                sinatra_request_span = Sinatra::Env.datadog_span(env, ::Sinatra::Base)

                sinatra_request_span.resource = span.resource

                Contrib::Analytics.set_measured(span)

                super
              end
            end
          end
        end
      end
    end
  end
end
