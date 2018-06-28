require 'excon'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'

module Datadog
  module Contrib
    module Excon
      # Middleware implements an excon-middleware for ddtrace instrumentation
      class Middleware < ::Excon::Middleware::Base
        SPAN_NAME = 'excon.request'.freeze
        DEFAULT_ERROR_HANDLER = lambda do |response|
          Ext::HTTP::ERROR_RANGE.cover?(response[:status])
        end

        def initialize(stack, options = {})
          super(stack)
          @options = Datadog.configuration[:excon].merge(options)
        end

        def request_call(datum)
          begin
            unless datum.key?(:datadog_span)
              tracer.trace(SPAN_NAME).tap do |span|
                datum[:datadog_span] = span
                annotate!(span, datum)
                propagate!(span, datum) if distributed_tracing?
              end
            end
          rescue StandardError => e
            Datadog::Tracer.log.debug(e.message)
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

        def tracer
          @options[:tracer]
        end

        def distributed_tracing?
          @options[:distributed_tracing] == true && tracer.enabled
        end

        def error_handler
          @options[:error_handler] || DEFAULT_ERROR_HANDLER
        end

        def split_by_domain?
          @options[:split_by_domain] == true
        end

        def annotate!(span, datum)
          span.resource = datum[:method].to_s.upcase
          span.service = service_name(datum)
          span.span_type = Ext::HTTP::TYPE
          span.set_tag(Ext::HTTP::URL, datum[:path])
          span.set_tag(Ext::HTTP::METHOD, datum[:method].to_s.upcase)
          span.set_tag(Ext::NET::TARGET_HOST, datum[:host])
          span.set_tag(Ext::NET::TARGET_PORT, datum[:port].to_s)
        end

        def handle_response(datum)
          if datum.key?(:datadog_span)
            datum[:datadog_span].tap do |span|
              return span if span.finished?

              if datum.key?(:response)
                response = datum[:response]
                if error_handler.call(response)
                  span.set_error(["Error #{response[:status]}", response[:body]])
                end
                span.set_tag(Ext::HTTP::STATUS_CODE, response[:status])
              end
              span.set_error(datum[:error]) if datum.key?(:error)
              span.finish
              datum.delete(:datadog_span)
            end
          end
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end

        def propagate!(span, datum)
          Datadog::HTTPPropagator.inject!(span.context, datum[:headers])
        end

        def service_name(datum)
          # TODO: Change this to implement more sensible multiplexing
          split_by_domain? ? datum[:host] : @options[:service_name]
        end
      end
    end
  end
end
