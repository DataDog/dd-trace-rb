# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module Rack
        # Patcher for Rack integration
        module Patcher
          def self.patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
