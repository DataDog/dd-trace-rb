# typed: true
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/grape/ext'
require 'ddtrace/contrib/grape/instrumentation'
require 'ddtrace/contrib/grape/integration'
require 'ddtrace/contrib/patcher'

module Datadog
  module Tracing
    module Contrib
      module Grape
        # Patcher enables patching of 'grape' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Patch endpoints
            ::Grape::Endpoint.include(Instrumentation)

            # Subscribe to ActiveSupport events
            Endpoint.subscribe
          end
        end
      end
    end
  end
end
