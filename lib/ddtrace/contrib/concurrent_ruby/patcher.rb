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
          require 'ddtrace/contrib/concurrent_ruby/promises_future_patch'
          patch_promises_future
        end

        # Propagate tracing context in Concurrent::Future
        def patch_future
          ::Concurrent::Future.prepend(FuturePatch) if defined?(::Concurrent::Future)
        end

        # Propagate tracing context in Concurrent::Promises::Future
        def patch_promises_future
          ::Concurrent::Promises.singleton_class.prepend(PromisesFuturePatch) if defined?(::Concurrent::Promises::Future)
        end
      end
    end
  end
end
