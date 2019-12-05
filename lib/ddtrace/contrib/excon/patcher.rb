require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Excon
      # Patcher enables patching of 'excon' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/excon/middleware'
          add_middleware
        end

        def add_middleware
          ::Excon.defaults[:middlewares] = Middleware.around_default_stack
        end
      end
    end
  end
end
