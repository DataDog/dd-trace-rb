require 'sinatra/base'

require 'ddtrace/ext/app_types'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/http'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/utils/header_tagger'

sinatra_vs = Gem::Version.new(Sinatra::VERSION)
sinatra_min_vs = Gem::Version.new('1.4.0')
if sinatra_vs < sinatra_min_vs
  raise "sinatra version #{sinatra_vs} is not supported yet " \
          + "(supporting versions >=#{sinatra_min_vs})"
end

Datadog::Tracer.log.info("activating instrumentation for sinatra #{sinatra_vs}")

module Datadog
  module Contrib
    module Sinatra
      # Datadog::Contrib::Sinatra::Tracer is a Sinatra extension which traces
      # requests.
      module Tracer
        include Base

        ENV_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
        ENV_ROUTE = 'datadog.sinatra_route'.freeze

        register_as :sinatra

        option :service_name, default: 'sinatra', depends_on: [:tracer] do |value|
          get_option(:tracer).set_service_info(value, 'sinatra', Ext::AppTypes::WEB)
          value
        end

        option :tracer, default: Datadog.tracer
        option :resource_script_names, default: false
        option :distributed_tracing, default: false
        option :headers, default: Utils::HeaderTagger::DEFAULT_HEADERS

        def route(verb, action, *)
          # Keep track of the route name when the app is instantiated for an
          # incoming request.
          condition do
            # If the option to prepend script names is enabled, then
            # prepend the script name from the request onto the action.
            request.env[ENV_ROUTE] = if Datadog.configuration[:sinatra][:resource_script_names]
                                       "#{request.script_name}#{action}"
                                     else
                                       action
                                     end
          end

          super
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def self.registered(app)
          ::Sinatra::Base.module_eval do
            def render(engine, data, *)
              output = ''
              tracer = Datadog.configuration[:sinatra][:tracer]
              if tracer.enabled
                tracer.trace('sinatra.render_template', span_type: Datadog::Ext::HTTP::TEMPLATE) do |span|
                  # If data is a string, it is a literal template and we don't
                  # want to record it.
                  span.set_tag('sinatra.template_name', data) if data.is_a? Symbol
                  output = super
                end
              else
                output = super
              end

              output
            end
          end

          app.before do
            return unless Datadog.configuration[:sinatra][:tracer].enabled

            tracer = Datadog.configuration[:sinatra][:tracer]
            distributed_tracing = Datadog.configuration[:sinatra][:distributed_tracing]

            if distributed_tracing && tracer.provider.context.trace_id.nil?
              context = HTTPPropagator.extract(request.env)
              tracer.provider.context = context if context.trace_id
            end

            span = tracer.trace('sinatra.request',
                                service: Datadog.configuration[:sinatra][:service_name],
                                span_type: Datadog::Ext::HTTP::TYPE)
            span.set_tag(Datadog::Ext::HTTP::URL, request.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, request.request_method)

            request.env[ENV_REQUEST_SPAN] = span
          end

          app.after do
            return unless Datadog.configuration[:sinatra][:tracer].enabled

            span = request.env[ENV_REQUEST_SPAN]
            span.resource = "#{request.request_method} #{request.env[ENV_ROUTE]}"
            span.set_tag('sinatra.route.path', request.env[ENV_ROUTE])
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.status)
            span.set_error(env['sinatra.error']) if response.server_error?

            Datadog::Utils::HeaderTagger.tag_whitelisted_headers(
                span,
                Datadog.configuration[:sinatra][:headers][:request],
                Datadog::Utils::HeaderTagger::RackRequest,
                request.env
            )

            Datadog::Utils::HeaderTagger.tag_whitelisted_headers(
                span,
                Datadog.configuration[:sinatra][:headers][:response],
                Datadog::Utils::HeaderTagger::RackResponse,
                response.headers
            )

            span.finish
          end
        end
      end
    end
  end
end

# rubocop:disable Style/Documentation
module Sinatra
  register Datadog::Contrib::Sinatra::Tracer
end
