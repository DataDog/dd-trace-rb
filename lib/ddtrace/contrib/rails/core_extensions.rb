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

  # RailsActionPatcher contains functions to patch Rails action controller instrumentation
  module RailsActionPatcher
    module_function

    def patch_action_controller
      patch_process_action
    end

    def patch_process_action
      ::ActionController::Instrumentation.class_eval do
        def process_action_with_datadog(*args)
          # mutable payload that is sent to both signals so that
          # the tracing context can be propagated; used to propagate the
          # request span without relying in the spans order, it ensures
          # that the span is finished no matter what
          raw_payload = {
            controller: self.class.name,
            action: action_name,
            tracing_context: {}
          }

          ActiveSupport::Notifications.instrument('!datadog.start_processing.action_controller', raw_payload)
        ensure
          ActiveSupport::Notifications.instrument('!datadog.finish_processing.action_controller', raw_payload) do |payload|
            result = process_action_without_datadog(*args)
            payload[:status] = response.status
            result
          end
        end

        alias_method :process_action_without_datadog, :process_action
        alias_method :process_action, :process_action_with_datadog
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
      patch_cache_store_instrument
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
          ActiveSupport::Notifications.instrument('start_cache_read.active_support')
          read_without_datadog(*args, &block)
        end
      end
    end

    def patch_cache_store_fetch
      cache_store_class(:fetch).class_eval do
        alias_method :fetch_without_datadog, :fetch
        def fetch(*args, &block)
          ActiveSupport::Notifications.instrument('start_cache_fetch.active_support')
          fetch_without_datadog(*args, &block)
        end
      end
    end

    def patch_cache_store_write
      cache_store_class(:write).class_eval do
        alias_method :write_without_datadog, :write
        def write(*args, &block)
          ActiveSupport::Notifications.instrument('start_cache_write.active_support')
          write_without_datadog(*args, &block)
        end
      end
    end

    def patch_cache_store_delete
      cache_store_class(:delete).class_eval do
        alias_method :delete_without_datadog, :delete
        def delete(*args, &block)
          ActiveSupport::Notifications.instrument('start_cache_delete.active_support')
          delete_without_datadog(*args, &block)
        end
      end
    end

    def patch_cache_store_instrument
      # by default, Rails 3 doesn't instrument the cache system so we should turn it on
      # using the ActiveSupport::Cache::Store.instrument= function. Unfortunately, early
      # versions of Rails use a Thread.current store that is not compatible with some
      # application servers like Passenger.
      # More details: https://github.com/rails/rails/blob/v3.2.22.5/activesupport/lib/active_support/cache.rb#L175-L177
      return unless ::Rails::VERSION::MAJOR.to_i == 3
      ::ActiveSupport::Cache::Store.singleton_class.class_eval do
        # Add the instrument function that Rails 3.x uses
        # to know if the underlying cache should be instrumented or not. By default,
        # we force that instrumentation if the Rails application is auto instrumented.
        def instrument
          true
        end
      end
    end
  end
end
