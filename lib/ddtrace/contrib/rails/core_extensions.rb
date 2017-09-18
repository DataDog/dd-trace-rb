module Datadog
  # RailsRendererPatcher contains function to patch Rails rendering libraries.
  module RailsRendererPatcher
    module_function

    def patch_renderer
      patch_renderer_render_template
      patch_renderer_render_partial
    end

    def patch_renderer_render_template
      if defined?(::ActionView::TemplateRenderer)
        ::ActionView::TemplateRenderer.class_eval do
          alias_method :render_without_datadog, :render
          alias_method :render_template_without_datadog, :render_template

          def render(context, options)
            # create a tracing context and start the rendering span
            @tracing_context = {}
            ::ActiveSupport::Notifications.instrument('start_render_template.action_view', tracing_context: @tracing_context)
            render_without_datadog(context, options)
          rescue Exception => e
            # attach the exception to the tracing context if any
            @tracing_context[:exception] = e
            raise e
          ensure
            # ensure that the template `Span` is finished even during exceptions
            ::ActiveSupport::Notifications.instrument('finish_render_template.action_view', tracing_context: @tracing_context)
          end

          def render_template(template, layout_name = nil, locals = nil)
            # update the tracing context with computed values before the rendering
            @tracing_context[:template_name] = Datadog::Contrib::Rails::Utils.normalize_template_name(template.identifier)
            @tracing_context[:layout] = layout_name[:virtual_path]
            render_template_without_datadog(template, layout_name, locals)
          end
        end
      else # Rails < 3.1 TODO: modularize changes above to avoid duplication
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
