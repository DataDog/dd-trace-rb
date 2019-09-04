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

          def patched?
            done?(:action_controller)
          end

          def patch
            do_once(:action_controller) do
              begin
                patch_action_controller_metal
              rescue StandardError => e
                Datadog::Tracer.log.error("Unable to apply ActionController integration: #{e}")
              end
            end
          end

          def patch_action_controller_metal
            do_once(:patch_action_controller_metal) do
              ::ActionController::Metal.send(:prepend, ActionController::Instrumentation::Metal)
            end
          end
        end
      end
    end
  end
end
