require 'faraday'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/propagation/http_propagator'

module Datadog
  module Contrib
    module Faraday
      # Middleware implements a faraday-middleware for ddtrace instrumentation
      class Middleware < ::Faraday::Middleware
        include Ext::DistributedTracing

        def initialize(app, options = {})
          super(app)
          @options = Datadog.configuration[:faraday].merge(options)
          @tracer = Pin.get_from(::Faraday).tracer
          setup_service!
        end

        def call(env)
          tracer.trace(NAME) do |span|
            annotate!(span, env)
            propagate!(span, env) if options[:distributed_tracing] && tracer.enabled
            app.call(env).on_complete { |resp| handle_response(span, resp) }
          end
        end

        private

        attr_reader :app, :options, :tracer

        def annotate!(span, env)
          span.resource = env[:method].to_s.upcase
          span.service = service_name(env)
          span.span_type = Ext::HTTP::TYPE
          span.set_tag(Ext::HTTP::URL, env[:url].path)
          span.set_tag(Ext::HTTP::METHOD, env[:method].to_s.upcase)
          span.set_tag(Ext::NET::TARGET_HOST, env[:url].host)
          span.set_tag(Ext::NET::TARGET_PORT, env[:url].port)
        end

        def handle_response(span, env)
          if options.fetch(:error_handler).call(env)
            span.set_error(["Error #{env[:status]}", env[:body]])
          end

          span.set_tag(Ext::HTTP::STATUS_CODE, env[:status])
        end

        def propagate!(span, env)
          Datadog::HTTPPropagator.inject!(span.context, env[:request_headers])
        end

        def service_name(env)
          return env[:url].host if options[:split_by_domain]

          options[:service_name]
        end

        def setup_service!
          return if options[:service_name] == Datadog.configuration[:faraday][:service_name]

          Patcher.register_service(options[:service_name])
        end
      end
    end
  end
end
