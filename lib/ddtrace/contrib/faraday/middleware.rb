require 'faraday'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/faraday/ext'

module Datadog
  module Contrib
    module Faraday
      # Middleware implements a faraday-middleware for ddtrace instrumentation
      class Middleware < ::Faraday::Middleware
        include Datadog::Ext::DistributedTracing

        def initialize(app, options = {})
          super(app)
          @options = datadog_configuration.to_h.merge(options)
          setup_service!
        end

        def call(env)
          tracer.trace(Ext::SPAN_REQUEST) do |span|
            annotate!(span, env)
            propagate!(span, env) if options[:distributed_tracing] && tracer.enabled
            app.call(env).on_complete { |resp| handle_response(span, resp) }
          end
        end

        private

        attr_reader :app, :options

        def annotate!(span, env)
          span.resource = env[:method].to_s.upcase
          span.service = service_name(env)
          span.span_type = Datadog::Ext::HTTP::TYPE

          # Set analytics sample rate
          if analytics_enabled?
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate)
          end

          span.set_tag(Datadog::Ext::HTTP::URL, env[:url].path)
          span.set_tag(Datadog::Ext::HTTP::METHOD, env[:method].to_s.upcase)
          span.set_tag(Datadog::Ext::NET::TARGET_HOST, env[:url].host)
          span.set_tag(Datadog::Ext::NET::TARGET_PORT, env[:url].port)
        end

        def handle_response(span, env)
          if options.fetch(:error_handler).call(env)
            span.set_error(["Error #{env[:status]}", env[:body]])
          end

          span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, env[:status])
        end

        def propagate!(span, env)
          Datadog::HTTPPropagator.inject!(span.context, env[:request_headers])
        end

        def datadog_configuration
          Datadog.configuration[:faraday]
        end

        def tracer
          options[:tracer]
        end

        def service_name(env)
          return env[:url].host if options[:split_by_domain]

          options[:service_name]
        end

        def analytics_enabled?
          Contrib::Analytics.enabled?(options[:analytics_enabled])
        end

        def analytics_sample_rate
          options[:analytics_sample_rate]
        end

        def setup_service!
          return if options[:service_name] == datadog_configuration[:service_name]

          Patcher.register_service(options[:service_name])
        end
      end
    end
  end
end
