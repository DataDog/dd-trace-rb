# typed: true
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/active_support/cache/patcher'

module Datadog
  module Tracing
    module Contrib
      module ActiveSupport
        # Patcher enables patching of 'active_support' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Cache::Patcher.patch
          end
        end
      end
    end
  end
end
