require 'ddtrace/contrib/patcher'

module Datadog
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
          require 'ddtrace/contrib/concurrent_ruby/future_patch'
          patch_future
        end

        # Propagate tracing context in Concurrent::Future
        def patch_future
          ::Concurrent::Future.send(:include, FuturePatch)
        end
      end
    end
  end
end
