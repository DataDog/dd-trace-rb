module Datadog
  # RailsPatcher contains function to patch the Rails libraries.
  module RailsPatcher
    module_function

    def patch_renderer
      ::ActionView::Renderer.class_eval do
        alias_method :render_template_without_datadog, :render_template
        def render_template(*args)
          ActiveSupport::Notifications.instrument('start_render_template.action_view')
          render_template_without_datadog(*args)
        end
      end

      ::ActionView::PartialRenderer.class_eval do
        alias_method :render_partial_without_datadog, :render_partial
        def render_partial(*args)
          ActiveSupport::Notifications.instrument('start_render_partial.action_view')
          render_partial_without_datadog(*args)
        end
      end
    end

    def patch_cache_store
      # When Redis is used, we can't only patch Cache::Store as it is
      # Cache::RedisStore, a sub-class of it that is used, in practice.
      # We need to do a per-method monkey patching as some of them might
      # be redefined, and some of them not. The latest version of redis-activesupport
      # redefines write but leaves untouched read and delete:
      # https://github.com/redis-store/redis-activesupport/blob/master/lib/active_support/cache/redis_store.rb

      { read: 'start_cache_read.active_support',
        fetch: 'start_cache_fetch.active_support',
        write: 'start_cache_write.active_support',
        delete: 'start_cache_delete.active_support' }.each do |k, v|
        c = if defined?(::ActiveSupport::Cache::RedisStore) &&
               ::ActiveSupport::Cache::RedisStore.instance_methods(false).include?(k)
              ::ActiveSupport::Cache::RedisStore
            else
              ::ActiveSupport::Cache::Store
            end
        Datadog::Tracer.log.debug("monkey patching #{c}.#{k} triggering #{v}")
        c.class_eval do
          k_without_datadog = "#{k}_without_datadog".to_sym
          alias_method k_without_datadog, k
          define_method k do |*args|
            ActiveSupport::Notifications.instrument(v)
            send(k_without_datadog, *args)
          end
        end
      end

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
