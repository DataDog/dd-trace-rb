require_relative '../../../../core/utils'
require_relative '../../../metadata/ext'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module ActiveSupport
        module Cache
          # Defines instrumentation for ActiveSupport caching
          # rubocop:disable Lint/RescueException
          module Instrumentation
            module_function

            def start_trace_cache(payload)
              return unless enabled?

              # In most of the cases Rails ``fetch()`` and ``read()`` calls are nested.
              # This check ensures that two reads are not nested since they don't provide
              # interesting details.
              # NOTE: the ``finish_trace_cache()`` is fired but it already has a safe-guard
              # to avoid any kind of issue.
              current_span = Tracing.active_span
              return if current_span.try(:name) == Ext::SPAN_CACHE &&
                (
                  payload[:action] == Ext::RESOURCE_CACHE_GET &&
                  current_span.try(:resource) == Ext::RESOURCE_CACHE_GET ||
                  payload[:action] == Ext::RESOURCE_CACHE_MGET &&
                  current_span.try(:resource) == Ext::RESOURCE_CACHE_MGET
                )

              tracing_context = payload.fetch(:tracing_context)

              # create a new ``Span`` and add it to the tracing context
              service = Datadog.configuration.tracing[:active_support][:cache_service]
              type = Ext::SPAN_TYPE_CACHE
              span = Tracing.trace(Ext::SPAN_CACHE, service: service, span_type: type)
              span.resource = payload.fetch(:action)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_CACHE)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, service)

              tracing_context[:dd_cache_span] = span
            rescue StandardError => e
              Datadog.logger.debug(e.message)
            end

            def finish_trace_cache(payload)
              return unless enabled?

              # retrieve the tracing context and continue the trace
              tracing_context = payload.fetch(:tracing_context)
              span = tracing_context[:dd_cache_span]
              return unless span && !span.finished?

              begin
                # discard parameters from the cache_store configuration
                if defined?(::Rails)
                  store, = *Array.wrap(::Rails.configuration.cache_store).flatten
                  span.set_tag(Ext::TAG_CACHE_BACKEND, store)
                end

                normalized_key = ::ActiveSupport::Cache.expand_cache_key(payload.fetch(:key))
                cache_key = Core::Utils.truncate(normalized_key, Ext::QUANTIZE_CACHE_MAX_KEY_SIZE)
                span.set_tag(Ext::TAG_CACHE_KEY, cache_key)

                span.set_error(payload[:exception]) if payload[:exception]
              ensure
                span.finish
              end
            rescue StandardError => e
              Datadog.logger.debug(e.message)
            end

            def finish_trace_cache_multi(payload)
              return unless enabled?

              # retrieve the tracing context and continue the trace
              tracing_context = payload.fetch(:tracing_context)
              span = tracing_context[:dd_cache_span]
              return unless span && !span.finished?

              begin
                # discard parameters from the cache_store configuration
                if defined?(::Rails)
                  store, = *Array.wrap(::Rails.configuration.cache_store).flatten
                  span.set_tag(Ext::TAG_CACHE_BACKEND, store)
                end
                normalized_keys = payload.fetch(:keys, []).map do |key|
                  ::ActiveSupport::Cache.expand_cache_key(key)
                end
                cache_keys = Core::Utils.truncate(normalized_keys, Ext::QUANTIZE_CACHE_MAX_KEY_SIZE)
                span.set_tag(Ext::TAG_CACHE_KEY_MULTI, cache_keys)

                span.set_error(payload[:exception]) if payload[:exception]
              ensure
                span.finish
              end
            rescue StandardError => e
              Datadog.logger.debug(e.message)
            end

            def enabled?
              Tracing.enabled? && Datadog.configuration.tracing[:active_support][:enabled]
            end

            # Defines instrumentation for ActiveSupport cache reading
            module Read
              def read(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_GET,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end

            # Defines instrumentation for ActiveSupport cache reading of multiple keys
            module ReadMulti
              def read_multi(*keys, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_MGET,
                  keys: keys,
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache_multi(payload)
              end
            end

            # Defines instrumentation for ActiveSupport cache fetching
            module Fetch
              def fetch(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_GET,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end

            # Defines instrumentation for ActiveSupport cache fetching of multiple keys
            module FetchMulti
              def fetch_multi(*args, &block)
                # extract options hash
                keys = args[-1].instance_of?(Hash) ? args[0..-2] : args
                payload = {
                  action: Ext::RESOURCE_CACHE_MGET,
                  keys: keys,
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache_multi(payload)
              end
            end

            # Defines instrumentation for ActiveSupport cache writing
            module Write
              def write(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_SET,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache(payload)
              end
            end

            # Defines instrumentation for ActiveSupport cache writing of multiple keys
            module WriteMulti
              def write_multi(hash, options = nil)
                payload = {
                  action: Ext::RESOURCE_CACHE_MSET,
                  keys: hash.keys,
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
                rescue Exception => e
                  payload[:exception] = [e.class.name, e.message]
                  payload[:exception_object] = e
                  raise e
                end
              ensure
                Instrumentation.finish_trace_cache_multi(payload)
              end
            end

            # Defines instrumentation for ActiveSupport cache deleting
            module Delete
              def delete(*args, &block)
                payload = {
                  action: Ext::RESOURCE_CACHE_DELETE,
                  key: args[0],
                  tracing_context: {}
                }

                begin
                  # process and catch cache exceptions
                  Instrumentation.start_trace_cache(payload)
                  super
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
          # rubocop:enable Lint/RescueException
        end
      end
    end
  end
end
