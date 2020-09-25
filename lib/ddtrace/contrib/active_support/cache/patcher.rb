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
            patch_cache_store_read_multi
            patch_cache_store_fetch
            patch_cache_store_fetch_multi
            patch_cache_store_write
            patch_cache_store_write_multi
            patch_cache_store_delete
          end

          def cache_store_class(meth)
            ::ActiveSupport::Cache::Store
          end

          def patch_cache_store_read
            cache_store_class(:read).send(:prepend, Cache::Instrumentation::Read)
          end

          def patch_cache_store_read_multi
            cache_store_class(:read_multi).send(:prepend, Cache::Instrumentation::ReadMulti)
          end

          def patch_cache_store_fetch
            cache_store_class(:fetch).send(:prepend, Cache::Instrumentation::Fetch)
          end

          def patch_cache_store_fetch_multi
            klass = cache_store_class(:fetch_multi)
            return unless klass.public_method_defined?(:fetch_multi)

            klass.send(:prepend, Cache::Instrumentation::FetchMulti)
          end

          def patch_cache_store_write
            cache_store_class(:write).send(:prepend, Cache::Instrumentation::Write)
          end

          def patch_cache_store_write_multi
            klass = cache_store_class(:write_multi)
            return unless klass.public_method_defined?(:write_multi)

            klass.send(:prepend, Cache::Instrumentation::WriteMulti)
          end

          def patch_cache_store_delete
            cache_store_class(:delete).send(:prepend, Cache::Instrumentation::Delete)
          end
        end
      end
    end
  end
end
