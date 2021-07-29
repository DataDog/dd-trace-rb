require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/grape/ext'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/grape/instrumentation'

module Datadog
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
          Datadog::Contrib::Grape::Endpoint.subscribe
        end
      end
    end
  end
end
