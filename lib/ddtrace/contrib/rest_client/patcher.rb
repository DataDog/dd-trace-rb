module Datadog
  module Contrib
    module RestClient
      # RestClient integration
      module Patcher
        include Base
        register_as :delayed_job

        option :service_name, default: 'rest_client'.freeze
        option :tracer, default: Datadog.tracer

        @patched = false

        class << self
          def patch
            return @patched if patched? || !defined?(::RestClient::Request)

            require 'ddtrace/ext/app_types'

            add_pin(::RestClient::Request)
            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply RestClient integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def unpatch
            @patched = false
          end

          def add_instrumentation(klass)
          end

          def add_pin(klass)
            Pin.new(get_option(:service_name), app: 'rest_client', app_type: Ext::AppTypes::WEB).onto(klass)
          end
        end
      end
    end
  end
end
