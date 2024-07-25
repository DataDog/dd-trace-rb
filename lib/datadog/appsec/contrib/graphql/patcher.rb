# frozen_string_literal: true

require_relative '../patcher'
require_relative 'gateway/watcher'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        # Patcher for AppSec on GraphQL
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            require_relative 'appsec_trace'
            Gateway::Watcher.watch
            ::GraphQL::Schema.trace_with(AppSecTrace)
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
