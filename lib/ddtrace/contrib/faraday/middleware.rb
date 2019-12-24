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
        include Contrib::Instrumentation

        def base_configuration
          Datadog.configuration[:faraday]
        end

        def initialize(app, options = {})
          super(app)
          merge_with_configuration!(options)
        end

        def call(env)
          @env = env
          trace(Ext::SPAN_REQUEST) do |span|
            annotate!(span, env)
            propagate!(span, env) if configuration[:distributed_tracing] && tracer.enabled
            app.call(env).on_complete { |resp| handle_response(span, resp) }
          end
        ensure
          @env = nil
        end

        private

        attr_reader :app

        def annotate!(span, env)
          span.resource = resource_name(env)
          span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND

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
          if configuration.fetch(:error_handler).call(env)
            span.set_error(["Error #{env[:status]}", env[:body]])
          end

          span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, env[:status])
        end

        def propagate!(span, env)
          Datadog::HTTPPropagator.inject!(span.context, env[:request_headers])
        end

        def service_name
          return @env[:url].host if configuration[:split_by_domain]

          configuration[:service_name]
        end

        def resource_name(env)
          env[:method].to_s.upcase
        end

        def analytics_enabled?
          Contrib::Analytics.enabled?(configuration[:analytics_enabled])
        end

        def analytics_sample_rate
          configuration[:analytics_sample_rate]
        end
      end
    end
  end
end
