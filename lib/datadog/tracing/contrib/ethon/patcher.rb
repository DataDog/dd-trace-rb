# typed: true

require 'datadog/tracing/contrib/ethon/integration'
require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
    module Contrib
      module Ethon
        # Patcher enables patching of 'ethon' module.
        module Patcher
          include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require 'datadog/tracing/contrib/ethon/easy_patch'
            require 'datadog/tracing/contrib/ethon/multi_patch'

            ::Ethon::Easy.include(EasyPatch)
            ::Ethon::Multi.include(MultiPatch)
          end
        end
      end
    end
  end
end
