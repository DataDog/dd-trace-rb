# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module Rack
        # Patcher for Rack integration
        module Patcher
          module_function

          def patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
