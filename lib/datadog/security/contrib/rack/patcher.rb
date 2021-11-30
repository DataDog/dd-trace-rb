# typed: ignore

require 'datadog/security/contrib/patcher'
require 'datadog/security/contrib/rack/integration'
require 'datadog/security/contrib/rack/gateway/watcher'

module Datadog
  module Security
    module Contrib
      module Rack
        # Patcher for Rack integration
        module Patcher
          include Datadog::Security::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            Gateway::Watcher.watch
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
