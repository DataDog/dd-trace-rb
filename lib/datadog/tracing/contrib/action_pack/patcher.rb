# frozen_string_literal: true

require_relative "../patcher"
require_relative "action_controller/patcher"
require_relative "action_dispatch/patcher"

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        # Patcher enables patching of 'action_pack' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            ActionController::Patcher.patch
            ActionDispatch::Patcher.patch
          end
        end
      end
    end
  end
end
