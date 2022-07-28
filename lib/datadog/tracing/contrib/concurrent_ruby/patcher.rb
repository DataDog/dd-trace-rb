# typed: true

require_relative '../patcher'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # Patcher enables patching of 'Future' class.
        module Patcher
          include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require_relative 'future_patch'
            patch_future
          end

          # Propagate tracing context in Concurrent::Future
          def patch_future
            ::Concurrent::Future.include(FuturePatch)
          end
        end
      end
    end
  end
end
