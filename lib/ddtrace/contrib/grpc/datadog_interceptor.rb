module Datadog
  module Contrib
    module GRPC
      # :nodoc:
      module DatadogInterceptor
        # :nodoc:
        class Base < ::GRPC::Interceptor
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

          def pin
            Pin.get_from(::GRPC)
          end

          def tracer
            pin.tracer
          end
        end

        require_relative 'datadog_interceptor/client'
        require_relative 'datadog_interceptor/server'
      end
    end
  end
end
