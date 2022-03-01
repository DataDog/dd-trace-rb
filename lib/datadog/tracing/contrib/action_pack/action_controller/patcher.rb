# typed: true

require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/action_pack/action_controller/instrumentation'

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        module ActionController
          # Patcher for ActionController components
          module Patcher
            include Contrib::Patcher

            module_function

            def target_version
              Integration.version
            end

            def patch
              ::ActionController::Metal.prepend(ActionController::Instrumentation::Metal)
            end
          end
        end
      end
    end
  end
end
