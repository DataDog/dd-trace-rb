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

          def target_version
            Integration.version
          end

          def patch
            patch_cache_store_read
            patch_cache_store_fetch
            patch_cache_store_write
            patch_cache_store_delete
          end

          def cache_store_class(meth)
            ::ActiveSupport::Cache::Store
          end

          def patch_cache_store_read
            cache_store_class(:read).send(:prepend, Cache::Instrumentation::Read)
          end

          def patch_cache_store_fetch
            cache_store_class(:fetch).send(:prepend, Cache::Instrumentation::Fetch)
          end

          def patch_cache_store_write
            cache_store_class(:write).send(:prepend, Cache::Instrumentation::Write)
          end

          def patch_cache_store_delete
            cache_store_class(:delete).send(:prepend, Cache::Instrumentation::Delete)
          end
        end
      end
    end
  end
end
