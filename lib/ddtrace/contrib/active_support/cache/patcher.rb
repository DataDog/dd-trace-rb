require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_support/cache/instrumentation'

module Datadog
  module Contrib
    module ActiveSupport
      module Cache
        # Patcher enables patching of 'active_support' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def patched?
            done?(:cache)
          end

          def patch
            do_once(:cache) do
              begin
                patch_cache_store_read
                patch_cache_store_fetch
                patch_cache_store_write
                patch_cache_store_delete
              rescue StandardError => e
                Datadog::Tracer.log.error("Unable to apply Active Support cache integration: #{e}")
              end
            end
          end

          def cache_store_class(meth)
            ::ActiveSupport::Cache::Store
          end

          def patch_cache_store_read
            do_once(:patch_cache_store_read) do
              cache_store_class(:read).send(:prepend, Cache::Instrumentation::Read)
            end
          end

          def patch_cache_store_fetch
            do_once(:patch_cache_store_fetch) do
              cache_store_class(:fetch).send(:prepend, Cache::Instrumentation::Fetch)
            end
          end

          def patch_cache_store_write
            do_once(:patch_cache_store_write) do
              cache_store_class(:write).send(:prepend, Cache::Instrumentation::Write)
            end
          end

          def patch_cache_store_delete
            do_once(:patch_cache_store_delete) do
              cache_store_class(:delete).send(:prepend, Cache::Instrumentation::Delete)
            end
          end
        end
      end
    end
  end
end
