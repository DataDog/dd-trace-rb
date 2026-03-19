# frozen_string_literal: true

require_relative '../../monitor'
require_relative 'gateway/request'
require_relative 'gateway/response'
require_relative 'gateway/watcher'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Patcher
          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            Monitor::Gateway::Watcher.watch
            Gateway::Watcher.watch
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
