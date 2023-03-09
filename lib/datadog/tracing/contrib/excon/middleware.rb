require 'excon'

require_relative '../../../core'
require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative 'ext'
require_relative '../http_annotation_helper'

module Datadog
  module Tracing
    module Contrib
      module Excon
        # Middleware implements an excon-middleware for ddtrace instrumentation
        class Middleware < ::Excon::Middleware::Base
          include Contrib::HttpAnnotationHelper

          DEFAULT_ERROR_HANDLER = lambda do |response|
            Tracing::Metadata::Ext::HTTP::ERROR_RANGE.cover?(response[:status])
          end

          def initialize(stack, options = {})
            super(stack)
            @default_options = datadog_configuration.options_hash.merge(options)
          end

          def request_call(datum)
            begin
              unless datum.key?(:datadog_span)
                @options = build_request_options!(datum)
                span = Tracing.trace(Ext::SPAN_REQUEST)
                trace = Tracing.active_trace
                datum[:datadog_span] = span
                annotate!(span, datum)
                propagate!(trace, span, datum) if distributed_tracing?

                span
              end
            rescue StandardError => e
              Datadog.logger.debug(e.message)
            end

            @stack.request_call(datum)
          end

          def response_call(datum)
            @stack.response_call(datum).tap do |d|
              handle_response(d)
            end
          end

          def error_call(datum)
            handle_response(datum)
            @stack.error_call(datum)
          end

          # Returns a child class of this trace middleware
          # With options given as defaults.
          def self.with(options = {})
            Class.new(self) do
              @options = options

              # rubocop:disable Style/TrivialAccessors
              def self.options
                @options
              end
              # rubocop:enable Style/TrivialAccessors

              # default_options in this case contains our specific middleware options
              # so we want it to take precedence in build_request_options
              def build_request_options!(datum)
                datadog_configuration(datum[:host]).options_hash.merge(@default_options)
              end

              def initialize(stack)
                super(stack, self.class.options)
              end
            end
          end

          # Returns a copy of the default stack with the trace middleware injected
          def self.around_default_stack
            ::Excon.defaults[:middlewares].dup.tap do |default_stack|
              # If the default stack contains a version of the trace middleware already...
              existing_trace_middleware = default_stack.find { |m| m <= Middleware }
              default_stack.delete(existing_trace_middleware) if existing_trace_middleware

              # Inject after the ResponseParser middleware
              response_middleware_index = default_stack.index(::Excon::Middleware::ResponseParser).to_i
              default_stack.insert(response_middleware_index + 1, self)
            end
          end

          private

          def analytics_enabled?
            Contrib::Analytics.enabled?(@options[:analytics_enabled])
          end

          def analytics_sample_rate
            @options[:analytics_sample_rate]
          end

          def distributed_tracing?
            @options[:distributed_tracing] == true && Tracing.enabled?
          end

          def error_handler
            @options[:error_handler] || DEFAULT_ERROR_HANDLER
          end

          def annotate!(span, datum)
            span.resource = datum[:method].to_s.upcase
            span.service = service_name(datum[:host], @options)
            span.span_type = Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND

            span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

            span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            # Tag as an external peer service
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, datum[:host])

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, datum[:path])
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, datum[:method].to_s.upcase)
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, datum[:host])
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, datum[:port])
          end

          def handle_response(datum)
            if datum.key?(:datadog_span)
              datum[:datadog_span].tap do |span|
                return span if span.finished?

                if datum.key?(:response)
                  response = datum[:response]
                  span.set_error(["Error #{response[:status]}", response[:body]]) if error_handler.call(response)
                  span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, response[:status])
                end
                span.set_error(datum[:error]) if datum.key?(:error)
                span.finish
                datum.delete(:datadog_span)
              end
            end
          rescue StandardError => e
            Datadog.logger.debug(e.message)
          end

          def propagate!(trace, span, datum)
            Tracing::Propagation::HTTP.inject!(trace, datum[:headers])
          end

          def build_request_options!(datum)
            @default_options.merge(datadog_configuration(datum[:host]).options_hash)
          end

          def datadog_configuration(host = :default)
            Datadog.configuration.tracing[:excon, host]
          end
        end
      end
    end
  end
end
