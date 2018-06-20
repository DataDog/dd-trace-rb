module Datadog
  module Contrib
    module GRPC
      # :nodoc:
      module DatadogInterceptor
        # :nodoc:
        class Base < ::GRPC::Interceptor
          attr_accessor :datadog_pin

          def initialize(options = {})
            datadog_pin_configuration { |c| yield(c) if block_given? }
          end

          def request_response(**keywords)
            trace(keywords) { yield }
          end

          def client_streamer(**keywords)
            trace(keywords) { yield }
          end

          def server_streamer(**keywords)
            trace(keywords) { yield }
          end

          def bidi_streamer(**keywords)
            trace(keywords) { yield }
          end

          private

          def datadog_pin_configuration
            pin = default_datadog_pin

            if block_given?
              pin = Pin.new(
                pin.service_name,
                app: pin.app,
                app_type: pin.app_type,
                tracer: pin.tracer
              )

              yield(pin)
            end

            pin.onto(self)

            pin
          end

          def default_datadog_pin
            Pin.get_from(::GRPC)
          end

          def tracer
            datadog_pin.tracer
          end
        end

        require_relative 'datadog_interceptor/client'
        require_relative 'datadog_interceptor/server'
      end
    end
  end
end
