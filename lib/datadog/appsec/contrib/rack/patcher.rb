# frozen_string_literal: true

require_relative "../../monitor"
require_relative "gateway/watcher"

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Patcher for Rack integration
        module Patcher
          def self.patched?
            !!Patcher.instance_variable_get(:@patched) # TODO: Patcher.flag_patched
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            Monitor::Gateway::Watcher.watch
            Gateway::Watcher.watch
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
