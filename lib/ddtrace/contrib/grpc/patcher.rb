# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module GRPC
      SERVICE = 'grpc'.freeze

      # Patcher enables patching of 'grpc' module.
      module Patcher
        include Base
        register_as :grpc, auto_patch: true
        option :tracer, default: Datadog.tracer
        option :service_name, default: SERVICE

        @patched = false

        module_function

        def patch
          return false unless compatible?
          return @patched if @patched

          require 'ddtrace/ext/grpc'
          require 'ddtrace/propagation/grpc_propagator'
          require 'ddtrace/contrib/grpc/datadog_interceptor'
          require 'ddtrace/contrib/grpc/interception_context'

          add_pin
          prepend_interceptor

          @patched = true
        rescue StandardError => e
          Datadog::Tracer.log.error("Unable to apply gRPC integration: #{e}")
        ensure
          @patched
        end

        def compatible?
          defined?(::GRPC::VERSION) && Gem::Version.new(::GRPC::VERSION) >= Gem::Version.new('0.10.0')
        end

        def patched?
          @patched
        end

        def add_pin
          Pin.new(
            get_option(:service_name),
            app: 'grpc',
            app_type: 'grpc',
            tracer: get_option(:tracer)
          ).onto(::GRPC)
        end

        def prepend_interceptor
          ::GRPC::InterceptionContext
            .prepend(::GRPC::InterceptionContext::InterceptWithDatadog)
        end
      end
    end
  end
end
