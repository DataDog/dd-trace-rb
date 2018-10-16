require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Excon
      # Patcher enables patching of 'excon' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:excon)
        end

        def patch
          do_once(:excon) do
            begin
              require 'ddtrace/contrib/excon/middleware'

              add_middleware
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Excon integration: #{e}")
            end
          end
        end

        def add_middleware
          ::Excon.defaults[:middlewares] = Middleware.around_default_stack
        end
      end
    end
  end
end
