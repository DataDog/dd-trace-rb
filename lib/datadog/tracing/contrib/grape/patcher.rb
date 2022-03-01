# typed: true

require 'datadog/tracing/contrib/grape/endpoint'
require 'datadog/tracing/contrib/grape/ext'
require 'datadog/tracing/contrib/grape/instrumentation'
require 'datadog/tracing/contrib/grape/integration'
require 'datadog/tracing/contrib/patcher'

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
