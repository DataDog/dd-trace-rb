module Datadog
  # RailsRendererPatcher contains function to patch Rails rendering libraries.
  module RailsRendererPatcher
    module_function

    def patch_renderer
      patch_renderer_render_template
      patch_renderer_render_partial
    end

    def patch_renderer_render_template
      if defined?(::ActionView::Renderer)
        ::ActionView::Renderer.class_eval do
          alias_method :render_template_without_datadog, :render_template
          def render_template(*args, &block)
            ActiveSupport::Notifications.instrument('start_render_template.action_view')
            render_template_without_datadog(*args, &block)
          end
        end
      else # Rails < 3.1
        ::ActionView::Template.class_eval do
          alias_method :render_template_without_datadog, :render
          def render(*args, &block)
            ActiveSupport::Notifications.instrument('start_render_template.action_view')
            render_template_without_datadog(*args, &block)
          end
        end
      end
    end

    def patch_renderer_render_partial
      if defined?(::ActionView::PartialRenderer)
        ::ActionView::PartialRenderer.class_eval do
          alias_method :render_partial_without_datadog, :render_partial
          def render_partial(*args, &block)
            ActiveSupport::Notifications.instrument('start_render_partial.action_view')
            render_partial_without_datadog(*args, &block)
          end
        end
      else # Rails < 3.1
        ::ActionView::Partials::PartialRenderer.class_eval do
          alias_method :render_partial_without_datadog, :render
          def render(*args, &block)
            ActiveSupport::Notifications.instrument('start_render_partial.action_view')
            render_partial_without_datadog(*args, &block)
          end
        end
      end
    end
  end

  # RailsCachePatcher contains function to patch Rails caching libraries.
  module RailsCachePatcher
    module_function

    def patch_cache_store
      patch_cache_store_read
      patch_cache_store_fetch
      patch_cache_store_write
      patch_cache_store_delete
    end

    def cache_store_class(k)
      # When Redis is used, we can't only patch Cache::Store as it is
      # Cache::RedisStore, a sub-class of it that is used, in practice.
      # We need to do a per-method monkey patching as some of them might
      # be redefined, and some of them not. The latest version of redis-activesupport
      # redefines write but leaves untouched read and delete:
      # https://github.com/redis-store/redis-activesupport/blob/master/lib/active_support/cache/redis_store.rb
      c = if defined?(::ActiveSupport::Cache::RedisStore) &&
             ::ActiveSupport::Cache::RedisStore.instance_methods(false).include?(k)
            ::ActiveSupport::Cache::RedisStore
          else
            ::ActiveSupport::Cache::Store
          end
      c
    end

    def patch_cache_store_read
      cache_store_class(:read).class_eval do
        alias_method :read_without_datadog, :read
        def read(*args, &block)
          raw_payload = {
            action: 'GET',
            key: args[0],
            tracing_context: {}
          }

          ActiveSupport::Notifications.instrument('!datadog.start_cache_tracing.active_support', raw_payload)

          ActiveSupport::Notifications.instrument('!datadog.finish_cache_tracing.active_support', raw_payload) do
            read_without_datadog(*args, &block)
          end
        end
      end
    end

    def patch_cache_store_fetch
      cache_store_class(:fetch).class_eval do
        alias_method :fetch_without_datadog, :fetch
        def fetch(*args, &block)
          raw_payload = {
            action: 'GET',
            key: args[0],
            tracing_context: {}
          }

          ActiveSupport::Notifications.instrument('!datadog.start_cache_tracing.active_support', raw_payload)

          ActiveSupport::Notifications.instrument('!datadog.finish_cache_tracing.active_support', raw_payload) do
            fetch_without_datadog(*args, &block)
          end
        end
      end
    end

    def patch_cache_store_write
      cache_store_class(:write).class_eval do
        alias_method :write_without_datadog, :write
        def write(*args, &block)
          raw_payload = {
            action: 'SET',
            key: args[0],
            tracing_context: {}
          }

          ActiveSupport::Notifications.instrument('!datadog.start_cache_tracing.active_support', raw_payload)

          ActiveSupport::Notifications.instrument('!datadog.finish_cache_tracing.active_support', raw_payload) do
            write_without_datadog(*args, &block)
          end
        end
      end
    end

    def patch_cache_store_delete
      cache_store_class(:delete).class_eval do
        alias_method :delete_without_datadog, :delete
        def delete(*args, &block)
          raw_payload = {
            action: 'DELETE',
            key: args[0],
            tracing_context: {}
          }

          ActiveSupport::Notifications.instrument('!datadog.start_cache_tracing.active_support', raw_payload)

          ActiveSupport::Notifications.instrument('!datadog.finish_cache_tracing.active_support', raw_payload) do
            delete_without_datadog(*args, &block)
          end
        end
      end
    end
  end
end
