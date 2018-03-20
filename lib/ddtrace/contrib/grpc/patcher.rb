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
        option :service_name, default: SERVICE, depends_on: [:tracer] do |value|
          get_option(:tracer).set_service_info(value, 'grpc', Ext::AppTypes::WEB)
          value
        end

        @patched = false

        module_function

        def patch
          if !@patched && compatible?
            require_relative 'datadog_client_interceptor'
            require_relative 'datadog_server_interceptor'

            ::GRPC.const_set('DatadogClientInterceptor', DatadogClientInterceptor)
            ::GRPC.const_set('DatadogServerInterceptor', DatadogServerInterceptor)
          end

          @patched = true
        rescue StandardError => e
          Datadog::Tracer.log.error("Unable to apply Redis integration: #{e}")
        ensure
          @patched
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
