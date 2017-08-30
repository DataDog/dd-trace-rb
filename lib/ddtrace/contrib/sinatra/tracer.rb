
require 'sinatra/base'

require 'ddtrace/ext/app_types'
require 'ddtrace/ext/errors'
require 'ddtrace/ext/http'

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
      # TracerCfg is used to manipulate the configuration of the Sinatra
      # tracing extension.
      class TracerCfg
        DEFAULT_CFG = {
          enabled: true,
          default_service: 'sinatra',
          tracer: Datadog.tracer,
          debug: false,
          trace_agent_hostname: Datadog::Writer::HOSTNAME,
          trace_agent_port: Datadog::Writer::PORT
        }.freeze()

        attr_accessor :cfg

        def initialize
          @cfg = DEFAULT_CFG.dup()
        end

        def configure(args = {})
          args.each do |name, value|
            self[name] = value
          end

          apply()
        end

        def apply
          Datadog::Tracer.debug_logging = @cfg[:debug]

          tracer = @cfg[:tracer]

          tracer.enabled = @cfg[:enabled]
          tracer.configure(hostname: @cfg[:trace_agent_hostname],
                           port: @cfg[:trace_agent_port])

          tracer.set_service_info(@cfg[:default_service], 'sinatra',
                                  Datadog::Ext::AppTypes::WEB)
        end

        def [](key)
          raise ArgumentError, "unknown setting '#{key}'" unless @cfg.key? key
          @cfg[key]
        end

        def []=(key, value)
          raise ArgumentError, "unknown setting '#{key}'" unless @cfg.key? key
          @cfg[key] = value
        end

        def enabled?
          @cfg[:enabled] && !@cfg[:tracer].nil?
        end
      end

      # Datadog::Contrib::Sinatra::Tracer is a Sinatra extension which traces
      # requests.
      module Tracer
        def route(verb, action, *)
          # Keep track of the route name when the app is instantiated for an
          # incoming request.
          condition do
            @datadog_route = action
          end

          super
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def self.registered(app)
          ::Sinatra::Base.module_eval do
            def render(engine, data, *)
              cfg = settings.datadog_tracer

              output = ''
              if cfg.enabled?
                tracer = cfg[:tracer]
                tracer.trace('sinatra.render_template') do |span|
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

          app.set :datadog_tracer, TracerCfg.new()

          app.configure do
            app.settings.datadog_tracer.apply()
          end

          app.before do
            cfg = settings.datadog_tracer
            return unless cfg.enabled?

            if instance_variable_defined? :@datadog_request_span
              if @datadog_request_span
                Datadog::Tracer.log.error('request span active in :before hook')
                @datadog_request_span.finish()
                @datadog_request_span = nil
              end
            end

            tracer = cfg[:tracer]

            span = tracer.trace('sinatra.request',
                                service: cfg.cfg[:default_service],
                                span_type: Datadog::Ext::HTTP::TYPE)
            span.set_tag(Datadog::Ext::HTTP::URL, request.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, request.request_method)

            @datadog_request_span = span
          end

          app.after do
            cfg = settings.datadog_tracer
            return unless cfg.enabled?

            span = @datadog_request_span
            begin
              unless span
                Datadog::Tracer.log.error('missing request span in :after hook')
                return
              end

              span.resource = "#{request.request_method} #{@datadog_route}"
              span.set_tag('sinatra.route.path', @datadog_route)
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.status)
              span.set_error(env['sinatra.error']) if response.server_error?
              span.finish()
            ensure
              @datadog_request_span = nil
            end
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
