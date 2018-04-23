require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module Excon
      # Responsible for hooking the instrumentation into Excon
      module Patcher
        include Base

        DEFAULT_SERVICE = 'excon'.freeze

        register_as :excon
        option :tracer, default: Datadog.tracer
        option :service_name, default: DEFAULT_SERVICE
        option :distributed_tracing, default: false
        option :split_by_domain, default: false
        option :error_handler, default: nil

        @patched = false

        module_function

        def patch
          return @patched if patched? || !compatible?

          require 'ddtrace/contrib/excon/middleware'

          add_middleware

          @patched = true
        rescue => e
          Tracer.log.error("Unable to apply Excon integration: #{e}")
          @patched
        end

        def patched?
          @patched
        end

        def compatible?
          defined?(::Excon)
        end

        def add_middleware
          ::Excon.defaults[:middlewares] = Middleware.around_default_stack
        end
      end
    end
  end
end
