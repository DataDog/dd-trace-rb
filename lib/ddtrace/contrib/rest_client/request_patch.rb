require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'restclient/request'

module Datadog
  module Contrib
    module RestClient
      # RestClient RequestPatch
      module RequestPatch
        REQUEST_TRACE_NAME = 'rest_client.request'.freeze

        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              alias_method :execute_without_datadog, :execute
              remove_method :execute
              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def execute(&block)
            execute_without_datadog(&block)
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

          def execute(&block)
            return super(&block) unless datadog_tracer.enabled

            datadog_trace_request do |span|
              if datadog_configuration[:distributed_tracing]
                Datadog::HTTPPropagator.inject!(span.context, processed_headers)
              end

              super(&block)
            end
          end

          def datadog_tag_request
            uri = URI.parse(url)
            @datadog_span.resource = method.to_s.upcase
            @datadog_span.set_tag(Ext::HTTP::URL, uri.path)
            @datadog_span.set_tag(Ext::HTTP::METHOD, method.to_s.upcase)
            @datadog_span.set_tag(Ext::NET::TARGET_HOST, uri.host)
            @datadog_span.set_tag(Ext::NET::TARGET_PORT, uri.port)
          end

          def datadog_trace_request
            @datadog_span = datadog_tracer.trace(REQUEST_TRACE_NAME,
                                                 span_type: Ext::HTTP::TYPE,
                                                 service: datadog_configuration[:service_name])

            datadog_tag_request
            response = yield @datadog_span

            @datadog_span.set_tag(Ext::HTTP::STATUS_CODE, response.code)
            response
          rescue ::RestClient::ExceptionWithResponse => e
            @datadog_span.set_error(e) if Ext::HTTP::ERROR_RANGE.cover?(e.http_code)
            @datadog_span.set_tag(Ext::HTTP::STATUS_CODE, e.http_code)

            raise e
            # rubocop:disable Lint/RescueException
          rescue Exception => e
            # rubocop:enable Lint/RescueException
            @datadog_span.set_error(e)

            raise e
          ensure
            @datadog_span.finish
          end

          def datadog_span
            if block_given?
              yield @datadog_span if @datadog_span
            else
              @datadog_span
            end
          end

          def datadog_tracer
            datadog_configuration[:tracer]
          end

          def datadog_configuration
            Datadog.configuration[:rest_client]
          end
        end
      end
    end
  end
end
