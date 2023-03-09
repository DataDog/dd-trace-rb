require_relative '../patcher'
require_relative 'action_controller/patcher'

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        # Patcher enables patching of 'action_pack' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ActionController::Patcher.patch
          end
        end
      end
    end
  end
end
