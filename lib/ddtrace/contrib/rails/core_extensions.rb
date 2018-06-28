module Datadog
  # RailsRendererPatcher contains function to patch Rails rendering libraries.
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/ModuleLength
  module RailsRendererPatcher
    include Datadog::Patcher

    SPAN_NAME_RENDER_PARTIAL = 'rails.render_partial'.freeze
    SPAN_NAME_RENDER_TEMPLATE = 'rails.render_template'.freeze
    TAG_LAYOUT = 'rails.layout'.freeze
    TAG_TEMPLATE_NAME = 'rails.template_name'.freeze

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
                Datadog::RailsRendererPatcher::SPAN_NAME_RENDER_TEMPLATE,
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
                  Datadog::RailsRendererPatcher::TAG_TEMPLATE_NAME,
                  template_name
                )
              end

              if layout
                active_datadog_span.set_tag(
                  Datadog::RailsRendererPatcher::TAG_LAYOUT,
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
              Datadog::RailsRendererPatcher::SPAN_NAME_RENDER_PARTIAL,
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
                  Datadog::RailsRendererPatcher::TAG_TEMPLATE_NAME,
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

        ::ActionController::Metal.send(:include, Datadog::Contrib::Rails::ActionControllerPatch)
      end
    end
  end

  # RailsCachePatcher contains function to patch Rails caching libraries.
  module RailsCachePatcher
    include Datadog::Patcher

    # Adds some common tracing code for caching actions
    module CacheTracing
      def datadog_trace_cache_with(action, key)
        value = nil

        # In most of the cases Rails ``fetch()`` and ``read()`` calls are nested.
        # This check ensures that two reads are not nested since they don't provide
        # interesting details.
        if nested_within_read?(action)
          value = yield
        else
          datadog_tracer.trace(
            'rails.cache'.freeze,
            resource: action,
            service: Datadog.configuration[:rails][:cache_service],
            span_type: Datadog::Ext::CACHE::TYPE
          ) do |span|
            begin
              value = yield
            ensure
              span.set_tag(
                'rails.cache.backend'.freeze,
                ::Rails.configuration.cache_store.to_a.flatten.first
              )
              span.set_tag(
                'rails.cache.key'.freeze,
                Datadog::Utils.truncate(key, Ext::CACHE::MAX_KEY_SIZE)
              )
            end
          end
        end

        value
      end

      def nested_within_read?(action)
        current_span = datadog_tracer.active_span
        if action == 'GET'.freeze \
           && current_span.try(:name) == 'rails.cache'.freeze \
           && current_span.try(:resource) == 'GET'.freeze
          true
        else
          false
        end
      end

      def datadog_tracer
        Datadog.configuration[:rails][:tracer]
      end
    end

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
          include ::Datadog::RailsCachePatcher::CacheTracing

          alias_method :read_without_datadog, :read

          def read(*args, &block)
            datadog_trace_cache_with('GET'.freeze, args[0]) { read_without_datadog(*args, &block) }
          end
        end
      end
    end

    def patch_cache_store_fetch
      do_once(:patch_cache_store_fetch) do
        cache_store_class(:fetch).class_eval do
          include ::Datadog::RailsCachePatcher::CacheTracing

          alias_method :fetch_without_datadog, :fetch

          def fetch(*args, &block)
            datadog_trace_cache_with('GET'.freeze, args[0]) { fetch_without_datadog(*args, &block) }
          end
        end
      end
    end

    def patch_cache_store_write
      do_once(:patch_cache_store_write) do
        cache_store_class(:write).class_eval do
          include ::Datadog::RailsCachePatcher::CacheTracing

          alias_method :write_without_datadog, :write

          def write(*args, &block)
            datadog_trace_cache_with('SET'.freeze, args[0]) { write_without_datadog(*args, &block) }
          end
        end
      end
    end

    def patch_cache_store_delete
      do_once(:patch_cache_store_delete) do
        cache_store_class(:delete).class_eval do
          include ::Datadog::RailsCachePatcher::CacheTracing

          alias_method :delete_without_datadog, :delete

          def delete(*args, &block)
            datadog_trace_cache_with('DELETE'.freeze, args[0]) { delete_without_datadog(*args, &block) }
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
