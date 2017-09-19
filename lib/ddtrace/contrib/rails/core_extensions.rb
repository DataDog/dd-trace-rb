module Datadog
  # RailsRendererPatcher contains function to patch Rails rendering libraries.
  module RailsRendererPatcher
    module_function

    def patch_renderer
      patch_renderer_render_template
      patch_renderer_render_partial
    end

    def tracing_block(klass)
      klass.class_eval do
        def render_with_datadog(*args, &block)
          # create a tracing context and start the rendering span
          # NOTE: Rails < 3.1 compatibility: preserve the tracing
          # context when a partial is rendered
          @tracing_context ||= {}
          if @tracing_context.empty?
            ::ActiveSupport::Notifications.instrument('start_render_template.action_view', tracing_context: @tracing_context)
          end
          render_without_datadog(*args)
        rescue Exception => e
          # attach the exception to the tracing context if any
          @tracing_context[:exception] = e
          raise e
        ensure
          # ensure that the template `Span` is finished even during exceptions
          ::ActiveSupport::Notifications.instrument('finish_render_template.action_view', tracing_context: @tracing_context)
        end

        def render_template_with_datadog(*args)
          # arguments based on render_template signature (stable since Rails 3.2)
          template = args[0]
          layout_name = args[1]

          # update the tracing context with computed values before the rendering
          template_name = template.try('identifier')
          template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(template_name)
          if layout_name.is_a?(String)
            # NOTE: Rails < 3.1 compatibility: the second argument is the layout name
            layout = layout_name
          else
            layout = layout_name.try(:[], 'virtual_path')
          end
          @tracing_context[:template_name] = template_name
          @tracing_context[:layout] = layout
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        ensure
          render_template_without_datadog(*args)
        end

        # method aliasing to patch the class
        alias_method :render_without_datadog, :render
        alias_method :render, :render_with_datadog

        if klass.private_method_defined? :render_template
          alias_method :render_template_without_datadog, :render_template
          alias_method :render_template, :render_template_with_datadog
        else
          # NOTE: Rails < 3.1 compatibility: the method name is different
          alias_method :render_template_without_datadog, :_render_template
          alias_method :_render_template, :render_template_with_datadog
        end
      end
    end

    def tracing_partial_block(klass)
      klass.class_eval do
        def render_with_datadog(*args, &block)
          # create a tracing context and start the rendering span
          @tracing_context = {}
          ::ActiveSupport::Notifications.instrument('start_render_partial.action_view', tracing_context: @tracing_context)
          render_without_datadog(*args)
        rescue Exception => e
          # attach the exception to the tracing context if any
          @tracing_context[:exception] = e
          raise e
        ensure
          # ensure that the template `Span` is finished even during exceptions
          ::ActiveSupport::Notifications.instrument('finish_render_partial.action_view', tracing_context: @tracing_context)
        end

        def render_partial_with_datadog(*args)
          # update the tracing context with computed values before the rendering
          template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(@template.try('identifier'))
          @tracing_context[:template_name] = template_name
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        ensure
          render_partial_without_datadog(*args)
        end

        # method aliasing to patch the class
        alias_method :render_without_datadog, :render
        alias_method :render, :render_with_datadog
        alias_method :render_partial_without_datadog, :render_partial
        alias_method :render_partial, :render_partial_with_datadog
      end
    end

    def patch_renderer_render_template
      if defined?(::ActionView::TemplateRenderer)
        tracing_block(::ActionView::TemplateRenderer)
      else
        # Rails < 3.1
        tracing_block(::ActionView::Rendering)
      end
    end

    def patch_renderer_render_partial
      if defined?(::ActionView::PartialRenderer)
        tracing_partial_block(::ActionView::PartialRenderer)
      else
        # Rails < 3.1
        tracing_partial_block(::ActionView::Partials::PartialRenderer)
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
