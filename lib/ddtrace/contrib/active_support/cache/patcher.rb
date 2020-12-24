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
            [
              Cache::Instrumentation::Decrement,
              Cache::Instrumentation::Read,
              Cache::Instrumentation::ReadMulti,
              Cache::Instrumentation::Fetch,
              Cache::Instrumentation::FetchMulti,
              Cache::Instrumentation::Write,
              Cache::Instrumentation::WriteMulti,
              Cache::Instrumentation::Delete,
            ].each do |instrumentation|
              cache_method = instrumentation.cache_method

              next unless cache_store_class(cache_method).public_method_defined?(cache_method)

              cache_store_class(cache_method).send(:prepend, instrumentation)

              # Because {ActiveSupport::Cache::Strategy::LocalCache} is prepended
              # to its host class, we can't modify its behavior by changing
              # {ActiveSupport::Cache::Strategy::LocalCache}'s class hierarchy.
              #
              # Our only option is to change the class hierarchy of host class.
              # For new classes, we add a callback to
              # {ActiveSupport::Cache::Strategy::LocalCache#prepended}.
              # But for existing classes, we don't have a way to reach them
              # through the {ActiveSupport::Cache::Strategy::LocalCache} object.
              # We resort to walking the {ObjectSpace} searching for them.
              local_cache_class.singleton_class.send(:prepend, Module.new do
                # We use `define_method` instead of `def` here to allow
                # for closure capture of `instrumentation`.
                define_method(:prepended) do |base|
                  base.prepend instrumentation #unless base.ancestors.include?(instrumentation)
                end
              end)

              ObjectSpace.each_object(local_cache_class) do |obj|
                obj.class.send(:prepend, instrumentation)
              end
            end
          end

          # Base class for all ActiveSupport cache implementations.
          def cache_store_class(_method)
            ::ActiveSupport::Cache::Store
          end

          # Mixin prepended to cache implementations with an extra local
          # cache layer.
          def local_cache_class
            ::ActiveSupport::Cache::Strategy::LocalCache
          end
        end
      end
    end
  end
end
