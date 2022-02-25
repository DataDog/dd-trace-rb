# typed: true

require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/action_pack/action_controller/patcher'

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
