# frozen_string_literal: true

require_relative "../../monitor"
require_relative "gateway/watcher"

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Patcher
          def self.patched?
            Patcher.instance_variable_get(:@patched)
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
