# typed: ignore
require 'faraday'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/propagation/http'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/faraday/ext'
require 'datadog/tracing/contrib/http_annotation_helper'

module Datadog
  module Tracing
    module Contrib
      module Faraday
        # Middleware implements a faraday-middleware for ddtrace instrumentation
        class Middleware < ::Faraday::Middleware
          include Contrib::HttpAnnotationHelper

          def initialize(app, options = {})
            super(app)
            @options = options
          end

          def call(env)
            # Resolve configuration settings to use for this request.
            # Do this once to reduce expensive regex calls.
            request_options = build_request_options!(env)

            Tracing.trace(Ext::SPAN_REQUEST) do |span, trace|
              annotate!(span, env, request_options)
              propagate!(trace, span, env) if request_options[:distributed_tracing] && Tracing.enabled?
              app.call(env).on_complete { |resp| handle_response(span, resp, request_options) }
            end
          end

          private

          attr_reader :app

          def annotate!(span, env, options)
            span.resource = resource_name(env)
            service_name(env[:url].host, options)
            span.service = options[:split_by_domain] ? env[:url].host : options[:service_name]
            span.span_type = Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND

            span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            # Tag as an external peer service
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, env[:url].host)

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(options[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, options[:analytics_sample_rate])
            end

            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, env[:url].path)
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, env[:method].to_s.upcase)
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, env[:url].host)
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, env[:url].port)
          end

          def handle_response(span, env, options)
            span.set_error(["Error #{env[:status]}", env[:body]]) if options.fetch(:error_handler).call(env)

            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, env[:status])
          end

          def propagate!(trace, span, env)
            Tracing::Propagation::HTTP.inject!(trace, env[:request_headers])
          end

          def resource_name(env)
            env[:method].to_s.upcase
          end

          def build_request_options!(env)
            datadog_configuration
              .options_hash # integration level settings
              .merge(datadog_configuration(env[:url].host).options_hash) # per-host override
              .merge(@options) # middleware instance override
          end

          def datadog_configuration(host = :default)
            Tracing.configuration[:faraday, host]
          end
        end
      end
    end
  end
end
