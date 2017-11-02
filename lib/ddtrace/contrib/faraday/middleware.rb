require 'faraday'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'

module Datadog
  module Contrib
    module Faraday
      # Middleware implements a faraday-middleware for ddtrace instrumentation
      class Middleware < ::Faraday::Middleware
        include Ext::DistributedTracing

        DEFAULT_ERROR_HANDLER = lambda do |env|
          Ext::HTTP::ERROR_RANGE.cover?(env[:status])
        end

        DEFAULT_OPTIONS = {
          distributed_tracing: false,
          split_by_domain: false,
          error_handler: DEFAULT_ERROR_HANDLER
        }.freeze

        def initialize(app, options = {})
          super(app)
          @options = DEFAULT_OPTIONS.merge(options)
        end

        def call(env)
          dd_pin.tracer.trace(SERVICE) do |span|
            annotate!(span, env)
            propagate!(span, env) if options[:distributed_tracing]
            app.call(env).on_complete { |resp| handle_response(span, resp) }
          end
        end

        private

        attr_reader :app, :options

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
          env[:request_headers][HTTP_HEADER_TRACE_ID] = span.trace_id.to_s
          env[:request_headers][HTTP_HEADER_PARENT_ID] = span.span_id.to_s
          return unless span.sampling_priority
          env[:request_headers][HTTP_HEADER_SAMPLING_PRIORITY] = span.sampling_priority.to_s
        end

        def dd_pin
          Pin.get_from(::Faraday)
        end

        def service_name(env)
          return env[:url].host if options[:split_by_domain]

          dd_pin.service
        end
      end
    end
  end
end
