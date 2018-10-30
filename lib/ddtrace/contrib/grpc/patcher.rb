require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/grpc/ext'

module Datadog
  module Contrib
    module GRPC
      # Patcher enables patching of 'grpc' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:grpc)
        end

        def patch
          do_once(:grpc) do
            begin
              require 'ddtrace/propagation/grpc_propagator'
              require 'ddtrace/contrib/grpc/datadog_interceptor'
              require 'ddtrace/contrib/grpc/intercept_with_datadog'

              add_pin
              prepend_interceptor
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply gRPC integration: #{e}")
            end
          end
        end

        def add_pin
          Pin.new(
            get_option(:service_name),
            app: Ext::APP,
            app_type: Datadog::Ext::AppTypes::WEB,
            tracer: get_option(:tracer)
          ).onto(::GRPC)
        end

        def prepend_interceptor
          ::GRPC::InterceptionContext
            .send(:prepend, Datadog::Contrib::GRPC::InterceptWithDatadog)
        end

        def get_option(option)
          Datadog.configuration[:grpc].get_option(option)
        end
      end
    end
  end
end
