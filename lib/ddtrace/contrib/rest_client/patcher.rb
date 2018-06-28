module Datadog
  module Contrib
    module RestClient
      # RestClient integration
      module Patcher
        include Base

        NAME = 'rest_client'.freeze
        register_as :rest_client

        option :service_name, default: NAME
        option :distributed_tracing, default: false
        option :tracer, default: Datadog.tracer

        @patched = false

        class << self
          def patch
            return @patched if patched? || !defined?(::RestClient::Request)

            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/rest_client/request_patch'

            add_instrumentation(::RestClient::Request)
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
            klass.send(:include, RequestPatch)
          end
        end
      end
    end
  end
end
