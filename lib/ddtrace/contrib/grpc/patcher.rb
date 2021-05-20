require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/grpc/ext'

module Datadog
  module Contrib
    module GRPC
      # Patcher enables patching of 'grpc' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/propagation/grpc_propagator'
          require 'ddtrace/contrib/grpc/datadog_interceptor'
          require 'ddtrace/contrib/grpc/intercept_with_datadog'

          prepend_interceptor
        end

        def prepend_interceptor
          ::GRPC::InterceptionContext
            .prepend(Datadog::Contrib::GRPC::InterceptWithDatadog)
        end
      end
    end
  end
end
