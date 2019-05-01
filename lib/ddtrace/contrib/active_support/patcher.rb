require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_support/ext'
require 'ddtrace/contrib/active_support/instrumentation'

module Datadog
  module Contrib
    module ActiveSupport
      # Patcher enables patching of 'active_support' module.
      # rubocop:disable Lint/RescueException
      # rubocop:disable Metrics/ModuleLength
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:active_support)
        end

        def patch
          do_once(:active_support) do
            begin
              patch_cache_store
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Active Support integration: #{e}")
            end
          end
        end

        def patch_cache_store
          do_once(:patch_cache_store) do
            patch_cache_store_read
            patch_cache_store_fetch
            patch_cache_store_write
            patch_cache_store_delete
            reload_cache_store
          end
        end

        def cache_store_class(meth)
          # When Redis is used, we can't only patch Cache::Store as it is
          # Cache::RedisStore, a sub-class of it that is used, in practice.
          # We need to do a per-method monkey patching as some of them might
          # be redefined, and some of them not. The latest version of redis-activesupport
          # redefines write but leaves untouched read and delete:
          # https://github.com/redis-store/redis-activesupport/blob/master/lib/active_support/cache/redis_store.rb
          if defined?(::ActiveSupport::Cache::RedisStore) \
            && ::ActiveSupport::Cache::RedisStore.instance_methods(false).include?(meth)
            ::ActiveSupport::Cache::RedisStore
          else
            ::ActiveSupport::Cache::Store
          end
        end

        def patch_cache_store_read
          do_once(:patch_cache_store_read) do
            cache_store_class(:read).class_eval do
              alias_method :read_without_datadog, :read

              def read(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_GET,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  read_without_datadog(*args, &block)
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end
          end
        end

        def patch_cache_store_fetch
          do_once(:patch_cache_store_fetch) do
            cache_store_class(:fetch).class_eval do
              alias_method :fetch_without_datadog, :fetch

              def fetch(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_GET,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  fetch_without_datadog(*args, &block)
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end
          end
        end

        def patch_cache_store_write
          do_once(:patch_cache_store_write) do
            cache_store_class(:write).class_eval do
              alias_method :write_without_datadog, :write

              def write(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_SET,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  write_without_datadog(*args, &block)
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end
          end
        end

        def patch_cache_store_delete
          do_once(:patch_cache_store_delete) do
            cache_store_class(:delete).class_eval do
              alias_method :delete_without_datadog, :delete

              def delete(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_DELETE,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  delete_without_datadog(*args, &block)
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end
          end
        end

        def self.reload_cache_store
          redis = Datadog.registry[:redis]
          return unless redis && redis.patcher.patched?

          return unless defined?(::ActiveSupport::Cache::RedisStore) &&
                        defined?(::Rails) &&
                        ::Rails.respond_to?(:cache) &&
                        ::Rails.cache.is_a?(::ActiveSupport::Cache::RedisStore)

          Tracer.log.debug('Reloading redis cache store')

          # backward compatibility: Rails 3.x doesn't have `cache=` method
          cache_store = ::Rails.configuration.cache_store
          cache_instance = ::ActiveSupport::Cache.lookup_store(cache_store)
          if ::Rails::VERSION::MAJOR.to_i == 3
            silence_warnings { Object.const_set 'RAILS_CACHE', cache_instance }
          elsif ::Rails::VERSION::MAJOR.to_i > 3
            ::Rails.cache = cache_instance
          end
        end
      end
    end
  end
end
