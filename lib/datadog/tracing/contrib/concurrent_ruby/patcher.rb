require_relative '../patcher'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # Patcher enables patching of 'Future' class.
        module Patcher
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
