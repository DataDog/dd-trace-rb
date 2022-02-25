# typed: true

require 'datadog/tracing/contrib/grpc/ext'
require 'datadog/tracing/contrib/grpc/integration'
require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
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
            require 'datadog/tracing/contrib/grpc/datadog_interceptor'
            require 'datadog/tracing/contrib/grpc/intercept_with_datadog'

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
end
