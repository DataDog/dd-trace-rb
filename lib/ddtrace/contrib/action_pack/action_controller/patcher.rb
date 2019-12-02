require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/action_pack/action_controller/instrumentation'

module Datadog
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
            ::ActionController::Metal.send(:prepend, ActionController::Instrumentation::Metal)
          end
        end
      end
    end
  end
end
