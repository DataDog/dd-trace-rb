require 'ddtrace/contrib/rails/ext'

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
      # rubocop:disable Metrics/BlockLength
      do_once(:patch_template_renderer) do
        klass.class_eval do
          def render_with_datadog(*args, &block)
            # NOTE: This check exists purely for Rails 3.0 compatibility.
            #       The 'if' part can be removed when support for Rails 3.0 is removed.
            if active_datadog_span
              render_without_datadog(*args, &block)
            else
              datadog_tracer.trace(
                Datadog::Contrib::Rails::Ext::SPAN_RENDER_TEMPLATE,
                span_type: Datadog::Ext::HTTP::TEMPLATE
              ) do |span|
                with_datadog_span(span) { render_without_datadog(*args, &block) }
              end
            end
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
              if template_name
                active_datadog_span.set_tag(
                  Datadog::Contrib::Rails::Ext::TAG_TEMPLATE_NAME,
                  template_name
                )
              end

              if layout
                active_datadog_span.set_tag(
                  Datadog::Contrib::Rails::Ext::TAG_LAYOUT,
                  layout
                )
              end
            rescue StandardError => e
              Datadog::Tracer.log.debug(e.message)
            end

            # execute the original function anyway
            render_template_without_datadog(*args)
          end

          private

          attr_accessor :active_datadog_span

          def datadog_tracer
            Datadog.configuration[:rails][:tracer]
          end

          def with_datadog_span(span)
            self.active_datadog_span = span
            yield
          ensure
            self.active_datadog_span = nil
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
            datadog_tracer.trace(
              Datadog::Contrib::Rails::Ext::SPAN_RENDER_PARTIAL,
              span_type: Datadog::Ext::HTTP::TEMPLATE
            ) do |span|
              with_datadog_span(span) { render_without_datadog(*args) }
            end
          end

          def render_partial_with_datadog(*args)
            begin
              template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(@template.try('identifier'))
              if template_name
                active_datadog_span.set_tag(
                  Datadog::Contrib::Rails::Ext::TAG_TEMPLATE_NAME,
                  template_name
                )
              end
            rescue StandardError => e
              Datadog::Tracer.log.debug(e.message)
            end

            # execute the original function anyway
            render_partial_without_datadog(*args)
          end

          private

          attr_accessor :active_datadog_span

          def datadog_tracer
            Datadog.configuration[:rails][:tracer]
          end

          def with_datadog_span(span)
            self.active_datadog_span = span
            yield
          ensure
            self.active_datadog_span = nil
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
        require 'ddtrace/contrib/rails/action_controller_patch'

        if defined?(::ActionController::Base)
          ::ActionController::Base.send(:include, Datadog::Contrib::Rails::ActionControllerPatch)
        end

        if defined?(::ActionController::API)
          ::ActionController::API.send(:include, Datadog::Contrib::Rails::ActionControllerPatch)
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
              action: Datadog::Contrib::Rails::Ext::RESOURCE_CACHE_GET,
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
              action: Datadog::Contrib::Rails::Ext::RESOURCE_CACHE_GET,
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
              action: Datadog::Contrib::Rails::Ext::RESOURCE_CACHE_SET,
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
              action: Datadog::Contrib::Rails::Ext::RESOURCE_CACHE_DELETE,
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
      return unless redis && redis.patcher.patched?

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
