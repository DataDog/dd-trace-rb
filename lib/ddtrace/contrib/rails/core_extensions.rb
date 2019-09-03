require 'ddtrace/contrib/rails/ext'

module Datadog
  # RailsActionPatcher contains functions to patch Rails action controller instrumentation
  module RailsActionPatcher
    include Datadog::Patcher

    module_function

    def patch_action_controller
      do_once(:patch_action_controller) do
        patch_process_action
      end
    end

    def patch_process_action
      do_once(:patch_process_action) do
        require 'ddtrace/contrib/rails/action_controller_patch'

        ::ActionController::Metal.send(:include, Datadog::Contrib::Rails::ActionControllerPatch)
      end
    end
  end
end
