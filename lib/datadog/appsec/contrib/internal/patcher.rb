# typed: ignore
# frozen_string_literal: true

require_relative '../patcher'
require_relative 'gateway/watcher'

module Datadog
  module AppSec
    module Contrib
      module Internal
        # Patcher for Rack integration
        module Patcher
          include ::Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched) # TODO: Patcher.flag_patched
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
