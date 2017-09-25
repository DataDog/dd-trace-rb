module Datadog
  # RailsRendererPatcher contains function to patch Rails rendering libraries.
  # rubocop:disable Lint/RescueException
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/BlockLength
  module RailsRendererPatcher
    module_function

    def patch_renderer
      if defined?(::ActionView::TemplateRenderer) && defined?(::ActionView::PartialRenderer)
        patch_template_renderer(::ActionView::TemplateRenderer)
        patch_partial_renderer(::ActionView::PartialRenderer)
      elsif defined?(::ActionView::Rendering) && defined?(::ActionView::Partials::PartialRenderer)
        # NOTE: Rails < 3.1 compatibility: different classes are used
        patch_template_renderer(::ActionView::Rendering)
        patch_partial_renderer(::ActionView::Partials::PartialRenderer)
      else
        Datadog::Tracer.log.debug('Expected Template/Partial classes not found; template rendering disabled')
      end
    end

    def patch_template_renderer(klass)
      klass.class_eval do
        def render_with_datadog(*args, &block)
          # create a tracing context and start the rendering span
          # NOTE: Rails < 3.1 compatibility: preserve the tracing
          # context when a partial is rendered
          @tracing_context ||= {}
          if @tracing_context.empty?
            ::ActiveSupport::Notifications.instrument(
              '!datadog.start_render_template.action_view',
              tracing_context: @tracing_context
            )
          end
          render_without_datadog(*args)
        rescue Exception => e
          # attach the exception to the tracing context if any
          @tracing_context[:exception] = e
          raise e
        ensure
          # ensure that the template `Span` is finished even during exceptions
          ::ActiveSupport::Notifications.instrument(
            '!datadog.finish_render_template.action_view',
            tracing_context: @tracing_context
          )
        end

        def render_template_with_datadog(*args)
          begin
            # arguments based on render_template signature (stable since Rails 3.2)
            template = args[0]
            layout_name = args[1]

            # update the tracing context with computed values before the rendering
            template_name = template.try('identifier')
            template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(template_name)
            layout = if layout_name.is_a?(String)
                       # NOTE: Rails < 3.1 compatibility: the second argument is the layout name
                       layout_name
                     else
                       layout_name.try(:[], 'virtual_path')
                     end
            @tracing_context[:template_name] = template_name
            @tracing_context[:layout] = layout
          rescue StandardError => e
            Datadog::Tracer.log.debug(e.message)
          end

          # execute the original function anyway
          render_template_without_datadog(*args)
        end

        # method aliasing to patch the class
        alias_method :render_without_datadog, :render
        alias_method :render, :render_with_datadog

        if klass.private_method_defined?(:render_template) || klass.method_defined?(:render_template)
          alias_method :render_template_without_datadog, :render_template
          alias_method :render_template, :render_template_with_datadog
        else
          # NOTE: Rails < 3.1 compatibility: the method name is different
          alias_method :render_template_without_datadog, :_render_template
          alias_method :_render_template, :render_template_with_datadog
        end
      end
    end

    def patch_partial_renderer(klass)
      klass.class_eval do
        def render_with_datadog(*args, &block)
          # create a tracing context and start the rendering span
          @tracing_context = {}
          ::ActiveSupport::Notifications.instrument(
            '!datadog.start_render_partial.action_view',
            tracing_context: @tracing_context
          )
          render_without_datadog(*args)
        rescue Exception => e
          # attach the exception to the tracing context if any
          @tracing_context[:exception] = e
          raise e
        ensure
          # ensure that the template `Span` is finished even during exceptions
          ::ActiveSupport::Notifications.instrument(
            '!datadog.finish_render_partial.action_view',
            tracing_context: @tracing_context
          )
        end

        def render_partial_with_datadog(*args)
          begin
            # update the tracing context with computed values before the rendering
            template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(@template.try('identifier'))
            @tracing_context[:template_name] = template_name
          rescue StandardError => e
            Datadog::Tracer.log.debug(e.message)
          end

          # execute the original function anyway
          render_partial_without_datadog(*args)
        end

        # method aliasing to patch the class
        alias_method :render_without_datadog, :render
        alias_method :render, :render_with_datadog
        alias_method :render_partial_without_datadog, :render_partial
        alias_method :render_partial, :render_partial_with_datadog
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
          # mutable payload with a tracing context that is used in two different
          # signals; it propagates the request span so that it can be finished
          # no matter what
          raw_payload = {
            controller: self.class.name,
            action: action_name,
            tracing_context: {}
          }

          # emits two different signals that start and finish the trace; this approach
          # mimics the original behavior that is available since Rails 3.0:
          # - https://github.com/rails/rails/blob/3-0-stable/actionpack/lib/action_controller/metal/instrumentation.rb#L17-L35
          # - https://github.com/rails/rails/blob/5-1-stable/actionpack/lib/action_controller/metal/instrumentation.rb#L17-L39
          ActiveSupport::Notifications.instrument('!datadog.start_processing.action_controller', raw_payload)

          # process the request and finish the trace
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
