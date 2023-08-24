# frozen_string_literal: true

require_relative '../../../../core/utils'
require_relative '../../../metadata/ext'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module ActiveSupport
        module Cache
          # Defines instrumentation for ActiveSupport caching
          module Instrumentation
            module_function

            # @param action [String] type of cache operation. Will be set as the span resource.
            # @param key [Object] redis cache key. Used for actions with a single key locator.
            # @param multi_key [Array<Object>] list of redis cache keys. Used for actions with a multiple key locators.
            def trace(action, key: nil, multi_key: nil)
              return yield unless enabled?

              # create a new ``Span`` and add it to the tracing context
              Tracing.trace(
                Ext::SPAN_CACHE,
                span_type: Ext::SPAN_TYPE_CACHE,
                service: Datadog.configuration.tracing[:active_support][:cache_service],
                resource: action
              ) do |span|
                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_CACHE)

                set_backend(span)
                set_cache_key(span, key, multi_key)

                yield
              end
            end

            # In most of the cases, `#fetch()` and `#read()` calls are nested.
            # Instrument both does not add any value.
            # This method checks if these two operations are nested.
            def nested_read?
              current_span = Tracing.active_span
              current_span && current_span.name == Ext::SPAN_CACHE && current_span.resource == Ext::RESOURCE_CACHE_GET
            end

            # (see #nested_read?)
            def nested_multiread?
              current_span = Tracing.active_span
              current_span && current_span.name == Ext::SPAN_CACHE && current_span.resource == Ext::RESOURCE_CACHE_MGET
            end

            def set_backend(span)
              if defined?(::Rails)
                store, = *Array.wrap(::Rails.configuration.cache_store).flatten
                span.set_tag(Ext::TAG_CACHE_BACKEND, store)
              end
            end

            def set_cache_key(span, single_key, multi_key)
              if multi_key
                resolved_key = multi_key.map { |key| ::ActiveSupport::Cache.expand_cache_key(key) }
                cache_key = Core::Utils.truncate(resolved_key, Ext::QUANTIZE_CACHE_MAX_KEY_SIZE)
                span.set_tag(Ext::TAG_CACHE_KEY_MULTI, cache_key)
              else
                resolved_key = ::ActiveSupport::Cache.expand_cache_key(single_key)
                cache_key = Core::Utils.truncate(resolved_key, Ext::QUANTIZE_CACHE_MAX_KEY_SIZE)
                span.set_tag(Ext::TAG_CACHE_KEY, cache_key)
              end
            end

            def enabled?
              Tracing.enabled? && Datadog.configuration.tracing[:active_support][:enabled]
            end

            # Defines instrumentation for ActiveSupport cache reading
            module Read
              def read(*args, &block)
                return super if Instrumentation.nested_read?

                Instrumentation.trace(Ext::RESOURCE_CACHE_GET, key: args[0]) { super }
              end
            end

            # Defines instrumentation for ActiveSupport cache reading of multiple keys
            module ReadMulti
              def read_multi(*keys, &block)
                return super if Instrumentation.nested_multiread?

                Instrumentation.trace(Ext::RESOURCE_CACHE_MGET, multi_key: keys) { super }
              end
            end

            # Defines instrumentation for ActiveSupport cache fetching
            module Fetch
              def fetch(*args, &block)
                return super if Instrumentation.nested_read?

                Instrumentation.trace(Ext::RESOURCE_CACHE_GET, key: args[0]) { super }
              end
            end

            # Defines instrumentation for ActiveSupport cache fetching of multiple keys
            module FetchMulti
              def fetch_multi(*args, &block)
                return super if Instrumentation.nested_multiread?

                keys = args[-1].instance_of?(Hash) ? args[0..-2] : args
                Instrumentation.trace(Ext::RESOURCE_CACHE_MGET, multi_key: keys) { super }
              end
            end

            # Defines instrumentation for ActiveSupport cache writing
            module Write
              def write(*args, &block)
                Instrumentation.trace(Ext::RESOURCE_CACHE_SET, key: args[0]) { super }
              end
            end

            # Defines instrumentation for ActiveSupport cache writing of multiple keys
            module WriteMulti
              def write_multi(hash, options = nil)
                Instrumentation.trace(Ext::RESOURCE_CACHE_MSET, multi_key: hash.keys) { super }
              end
            end

            # Defines instrumentation for ActiveSupport cache deleting
            module Delete
              def delete(*args, &block)
                Instrumentation.trace(Ext::RESOURCE_CACHE_DELETE, key: args[0]) { super }
              end
            end
          end
        end
      end
    end
  end
end
