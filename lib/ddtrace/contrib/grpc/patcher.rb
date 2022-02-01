# typed: true
require 'ddtrace/contrib/grpc/ext'
require 'ddtrace/contrib/grpc/integration'
require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module GRPC
      # Patcher enables patching of 'grpc' module.
      module Patcher
        include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'datadog/tracing/propagation/grpc'
          require 'ddtrace/contrib/grpc/datadog_interceptor'
          require 'ddtrace/contrib/grpc/intercept_with_datadog'

          prepend_interceptor
        end

        def prepend_interceptor
          ::GRPC::InterceptionContext
            .prepend(InterceptWithDatadog)
        end
      end
    end
  end
end
