require 'faraday'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/faraday/ext'
require 'ddtrace/contrib/http_annotation_helper'

module Datadog
  module Contrib
    module Faraday
      # Middleware implements a faraday-middleware for ddtrace instrumentation
      class Middleware < ::Faraday::Middleware
        include Datadog::Ext::DistributedTracing
        include Datadog::Contrib::HttpAnnotationHelper

        def initialize(app, options = {})
          super(app)
          @options = datadog_configuration.options_hash.merge(options)
        end

        def call(env)
          # Resolve configuration settings to use for this request.
          # Do this once to reduce expensive regex calls.
          request_options = build_request_options!(env)

          request_options[:tracer].trace(Ext::SPAN_REQUEST) do |span|
            annotate!(span, env, request_options)
            propagate!(span, env) if request_options[:distributed_tracing] && request_options[:tracer].enabled
            app.call(env).on_complete { |resp| handle_response(span, resp, request_options) }
          end
        end

        private

        attr_reader :app, :options

        def annotate!(span, env, options)
          span.resource = resource_name(env)
          service_name(env[:url].host, options)
          span.service = options[:split_by_domain] ? env[:url].host : options[:service_name]
          span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND

          # Set analytics sample rate
          if Contrib::Analytics.enabled?(options[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(span, options[:analytics_sample_rate])
          end

          span.set_tag(Datadog::Ext::HTTP::URL, env[:url].path)
          span.set_tag(Datadog::Ext::HTTP::METHOD, env[:method].to_s.upcase)
          span.set_tag(Datadog::Ext::NET::TARGET_HOST, env[:url].host)
          span.set_tag(Datadog::Ext::NET::TARGET_PORT, env[:url].port)
        end

        def handle_response(span, env, options)
          if options.fetch(:error_handler).call(env)
            span.set_error(["Error #{env[:status]}", env[:body]])
          end

          span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, env[:status])
        end

        def propagate!(span, env)
          Datadog::HTTPPropagator.inject!(span.context, env[:request_headers])
        end

        def resource_name(env)
          env[:method].to_s.upcase
        end

        def build_request_options!(env)
          datadog_configuration(env[:url].host).options_hash.merge(options)
        end

        def datadog_configuration(host = :default)
          Datadog.configuration[:faraday, host]
        end
      end
    end
  end
end
