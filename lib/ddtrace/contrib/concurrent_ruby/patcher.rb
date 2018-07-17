require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/concurrent_ruby/future_patch'

module Datadog
  module Contrib
    module ConcurrentRuby
      # Patcher enables patching of 'Future' class.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:concurrent_ruby)
        end

        def patch
          do_once(:concurrent_ruby) do
            begin
              patch_future
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Future integration: #{e}")
            end
          end
        end

        def patch_future
          ::Concurrent::Future.send(:include, FuturePatch)
        end
      end
    end
  end
end
