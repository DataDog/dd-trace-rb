module Datadog
  # RailsRendererPatcher contains function to patch Rails rendering libraries.
  # rubocop:disable Lint/RescueException
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/ModuleLength
  module RailsRendererPatcher
    include Datadog::Patcher

    module_function

    def patch_renderer
      do_once(:patch_renderer) do
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
    end

    def patch_template_renderer(klass)
      do_once(:patch_template_renderer) do
        klass.class_eval do
          def render_with_datadog(*args, &block)
            # create a tracing context and start the rendering span
            # NOTE: Rails < 3.1 compatibility: preserve the tracing
            # context when a partial is rendered
            @tracing_context ||= {}
            if @tracing_context.empty?
              Datadog::Contrib::Rails::ActionView.start_render_template(tracing_context: @tracing_context)
            end

            render_without_datadog(*args, &block)
          rescue Exception => e
            # attach the exception to the tracing context if any
            @tracing_context[:exception] = e
            raise e
          ensure
            # ensure that the template `Span` is finished even during exceptions
            Datadog::Contrib::Rails::ActionView.finish_render_template(tracing_context: @tracing_context)
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
    end

    def patch_partial_renderer(klass)
      do_once(:patch_partial_renderer) do
        klass.class_eval do
          def render_with_datadog(*args, &block)
            # Create a tracing context and start the rendering span
            tracing_context = {}
            Datadog::Contrib::Rails::ActionView.start_render_partial(tracing_context: tracing_context)
            tracing_contexts[current_span_id] = tracing_context

            render_without_datadog(*args)
          rescue Exception => e
            # attach the exception to the tracing context if any
            tracing_contexts[current_span_id][:exception] = e
            raise e
          ensure
            # Ensure that the template `Span` is finished even during exceptions
            # Remove the existing tracing context (to avoid leaks)
            tracing_contexts.delete(current_span_id)

            # Then finish the span associated with the context
            Datadog::Contrib::Rails::ActionView.finish_render_partial(tracing_context: tracing_context)
          end

          def render_partial_with_datadog(*args)
            begin
              # update the tracing context with computed values before the rendering
              template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(@template.try('identifier'))
              tracing_contexts[current_span_id][:template_name] = template_name
            rescue StandardError => e
              Datadog::Tracer.log.debug(e.message)
            end

            # execute the original function anyway
            render_partial_without_datadog(*args)
          end

          # Table of tracing contexts, one per partial/span, keyed by span_id
          # because there will be multiple concurrent contexts, depending on how
          # many partials are nested within one another.
          def tracing_contexts
            @tracing_contexts ||= {}
          end

          def current_span_id
            Datadog.configuration[:rails][:tracer].call_context.current_span.span_id
          end

          # method aliasing to patch the class
          alias_method :render_without_datadog, :render
          alias_method :render, :render_with_datadog
          alias_method :render_partial_without_datadog, :render_partial
          alias_method :render_partial, :render_partial_with_datadog
        end
      end
    end
  end

  # RailsActionPatcher contains functions to patch Rails action controller instrumentation
  module RailsActionPatcher
    include Datadog::Patcher

    module_function

    def patch_action_controller
      do_once(:patch_action_controller) do
        patch_process_action
      end
    end

    def patch_process_action
      do_once(:patch_process_action) do
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')
          # Patch Rails controller base class
          ::ActionController::Metal.send(:prepend, ActionControllerPatch)
        else
          # Rewrite module that gets composed into the Rails controller base class
          ::ActionController::Instrumentation.class_eval do
            def process_action_with_datadog(*args)
              # mutable payload with a tracing context that is used in two different
              # signals; it propagates the request span so that it can be finished
              # no matter what
              payload = {
                controller: self.class,
                action: action_name,
                headers: {
                  # The exception this controller was given in the request,
                  # which is typical if the controller is configured to handle exceptions.
                  request_exception: request.headers['action_dispatch.exception']
                },
                tracing_context: {}
              }

              begin
                # process and catch request exceptions
                Datadog::Contrib::Rails::ActionController.start_processing(payload)
                result = process_action_without_datadog(*args)
                payload[:status] = response.status
                result
              rescue Exception => e
                payload[:exception] = [e.class.name, e.message]
                payload[:exception_object] = e
                raise e
              end
            ensure
              Datadog::Contrib::Rails::ActionController.finish_processing(payload)
            end

            alias_method :process_action_without_datadog, :process_action
            alias_method :process_action, :process_action_with_datadog
          end
        end
      end
    end

    # ActionController patch for Ruby 2.0+
    module ActionControllerPatch
      def process_action(*args)
        # mutable payload with a tracing context that is used in two different
        # signals; it propagates the request span so that it can be finished
        # no matter what
        payload = {
          controller: self.class,
          action: action_name,
          headers: {
            # The exception this controller was given in the request,
            # which is typical if the controller is configured to handle exceptions.
            request_exception: request.headers['action_dispatch.exception']
          },
          tracing_context: {}
        }

        begin
          # process and catch request exceptions
          Datadog::Contrib::Rails::ActionController.start_processing(payload)
          result = super(*args)
          status = response_status
          payload[:status] = status unless status.nil?
          result
        rescue Exception => e
          payload[:exception] = [e.class.name, e.message]
          payload[:exception_object] = e
          raise e
        end
      ensure
        Datadog::Contrib::Rails::ActionController.finish_processing(payload)
      end

      # rubocop:disable Style/EmptyElse
      def response_status
        case response
        when ActionDispatch::Response
          response.status
        when Array
          status = response.first
          status.class <= Integer ? status : nil
        else
          nil
        end
      end
    end
  end

  # RailsCachePatcher contains function to patch Rails caching libraries.
  module RailsCachePatcher
    include Datadog::Patcher

    module_function

    def patch_cache_store
      do_once(:patch_cache_store) do
        patch_cache_store_read
        patch_cache_store_fetch
        patch_cache_store_write
        patch_cache_store_delete
        reload_cache_store
      end
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
      do_once(:patch_cache_store_read) do
        cache_store_class(:read).class_eval do
          alias_method :read_without_datadog, :read
          def read(*args, &block)
            payload = {
              action: 'GET',
              key: args[0],
              tracing_context: {}
            }

            begin
              # process and catch cache exceptions
              Datadog::Contrib::Rails::ActiveSupport.start_trace_cache(payload)
              read_without_datadog(*args, &block)
            rescue Exception => e
              payload[:exception] = [e.class.name, e.message]
              payload[:exception_object] = e
              raise e
            end
          ensure
            Datadog::Contrib::Rails::ActiveSupport.finish_trace_cache(payload)
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
              action: 'GET',
              key: args[0],
              tracing_context: {}
            }

            begin
              # process and catch cache exceptions
              Datadog::Contrib::Rails::ActiveSupport.start_trace_cache(payload)
              fetch_without_datadog(*args, &block)
            rescue Exception => e
              payload[:exception] = [e.class.name, e.message]
              payload[:exception_object] = e
              raise e
            end
          ensure
            Datadog::Contrib::Rails::ActiveSupport.finish_trace_cache(payload)
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
              action: 'SET',
              key: args[0],
              tracing_context: {}
            }

            begin
              # process and catch cache exceptions
              Datadog::Contrib::Rails::ActiveSupport.start_trace_cache(payload)
              write_without_datadog(*args, &block)
            rescue Exception => e
              payload[:exception] = [e.class.name, e.message]
              payload[:exception_object] = e
              raise e
            end
          ensure
            Datadog::Contrib::Rails::ActiveSupport.finish_trace_cache(payload)
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
              action: 'DELETE',
              key: args[0],
              tracing_context: {}
            }

            begin
              # process and catch cache exceptions
              Datadog::Contrib::Rails::ActiveSupport.start_trace_cache(payload)
              delete_without_datadog(*args, &block)
            rescue Exception => e
              payload[:exception] = [e.class.name, e.message]
              payload[:exception_object] = e
              raise e
            end
          ensure
            Datadog::Contrib::Rails::ActiveSupport.finish_trace_cache(payload)
          end
        end
      end
    end

    def self.reload_cache_store
      redis = Datadog.registry[:redis]
      return unless redis && redis.patched?

      return unless defined?(::ActiveSupport::Cache::RedisStore) &&
                    defined?(::Rails.cache) &&
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
