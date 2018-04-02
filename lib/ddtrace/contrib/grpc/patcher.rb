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
        option :client_stubs, default: []
        option :service_implementations, default: []

        @patched = false

        module_function

        def patch
          return false unless compatible?
          return @patched if @patched

          require_relative 'datadog_client_interceptor'
          require_relative 'datadog_server_interceptor'

          [DatadogClientInterceptor, DatadogServerInterceptor].each do |interceptor|
            Datadog::Pin.new(
              get_option(:service_name),
              tracer: get_option(:tracer)
            ).onto(interceptor)
          end

          get_option(:client_stubs).each do |stub|
            prepend_interceptor!(stub, DatadogClientInterceptor.new)
          end

          get_option(:service_implementations).each do |service_implementation|
            prepend_interceptor!(service_implementation, DatadogServerInterceptor.new)
          end

          @patched = true
        rescue StandardError => e
          Datadog::Tracer.log.error("Unable to apply gRPC integration: #{e}")
        ensure
          @patched
        end

        def prepend_interceptor!(grpc_object, datadog_interceptor)
          interceptor_registry = grpc_object.instance_variable_get(:@interceptors)
          interceptors = interceptor_registry.instance_variable_get(:@interceptors)
          interceptors.unshift(datadog_interceptor)

          grpc_object.instance_variable_set(
            :@interceptors,
            ::GRPC::InterceptorRegistry.new(interceptors)
          )

          grpc_object
        end

        def compatible?
          defined?(::GRPC::VERSION) && Gem::Version.new(::GRPC::VERSION) >= Gem::Version.new('0.10.0')
        end

        def patched?
          @patched
        end
      end
    end
  end
end
