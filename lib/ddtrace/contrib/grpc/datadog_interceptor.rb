# typed: ignore
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/grpc/ext'

module Datadog
  module Contrib
    module GRPC
      # :nodoc:
      module DatadogInterceptor
        # :nodoc:
        class Base < ::GRPC::Interceptor
          def initialize(options = {})
            add_datadog_pin! { |c| yield(c) if block_given? }
          end

          def request_response(**keywords, &block)
            trace(keywords, &block)
          end

          def client_streamer(**keywords, &block)
            trace(keywords, &block)
          end

          def server_streamer(**keywords, &block)
            trace(keywords, &block)
          end

          def bidi_streamer(**keywords, &block)
            trace(keywords, &block)
          end

          private

          def add_datadog_pin!
            pin = Datadog::Tracing.configure_onto(self, service_name: service_name)

            yield(pin) if block_given?

            pin
          end

          def datadog_configuration
            Datadog::Tracing.configuration[:grpc]
          end

          def service_name
            datadog_pin = Datadog::Tracing.configuration_for(self)
            (datadog_pin && datadog_pin[:service_name]) || datadog_configuration[:service_name]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end

          def error_handler
            datadog_configuration[:error_handler]
          end
        end

        require_relative 'datadog_interceptor/client'
        require_relative 'datadog_interceptor/server'
      end
    end
  end
end
