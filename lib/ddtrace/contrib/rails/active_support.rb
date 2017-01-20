require 'thread'
require 'ddtrace/ext/cache'

module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActiveSupport
        def self.instrument
          # patch Rails core components
          Datadog::RailsPatcher.patch_cache_store()

          # subscribe when a cache read starts being processed
          ::ActiveSupport::Notifications.subscribe('start_cache_read.active_support') do |*args|
            start_trace_cache('GET', *args)
          end

          # subscribe when a cache fetch starts being processed
          ::ActiveSupport::Notifications.subscribe('start_cache_fetch.active_support') do |*args|
            start_trace_cache('GET', *args)
          end

          # subscribe when a cache write starts being processed
          ::ActiveSupport::Notifications.subscribe('start_cache_write.active_support') do |*args|
            start_trace_cache('SET', *args)
          end

          # subscribe when a cache delete starts being processed
          ::ActiveSupport::Notifications.subscribe('start_cache_delete.active_support') do |*args|
            start_trace_cache('DELETE', *args)
          end

          # subscribe when a cache read has been processed
          ::ActiveSupport::Notifications.subscribe('cache_read.active_support') do |*args|
            trace_cache('GET', *args)
          end

          # subscribe when a cache write has been processed
          ::ActiveSupport::Notifications.subscribe('cache_write.active_support') do |*args|
            trace_cache('SET', *args)
          end

          # subscribe when a cache delete has been processed
          ::ActiveSupport::Notifications.subscribe('cache_delete.active_support') do |*args|
            trace_cache('DELETE', *args)
          end

          # by default, Rails 3 doesn't instrument the cache system
          return unless ::Rails::VERSION::MAJOR.to_i == 3
          ::ActiveSupport::Cache::Store.instrument = true
        end

        def self.create_span(tracer)
          service = ::Rails.configuration.datadog_trace.fetch(:default_cache_service)
          type = Datadog::Ext::CACHE::TYPE
          tracer.trace('rails.cache', service: service, span_type: type)
        end

        def self.get_key(resource)
          'datadog_activesupport_' + resource
        end

        def self.start_trace_cache(resource, *_args)
          key = get_key(resource)
          # This is mostly to trap the case of fetch/read. In some cases the framework
          # will call fetch but fetch won't call read. In some cases read can be called
          # alone. And in some cases they are nested. In all cases we want to have one
          # and only one span.
          return if Thread.current[key]
          create_span(::Rails.configuration.datadog_trace.fetch(:tracer))
          Thread.current[key] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.trace_cache(resource, _name, start, finish, _id, payload)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          key = get_key(resource)
          if Thread.current[key]
            # span was created by start_trace_cache, plan to re-use this one
            Thread.current[key] = false
          else
            # Create a span now, as start_trace_cache was not called.
            #
            # This could typically happen if, for some reason the monkey-patching
            # of the cache class did not work as expected. Doing this, we might
            # loose some interesting parentship between some spans, because this
            # span is created too late, and children won't "find" their parent.
            # But, it's better than no span at all, and it case there is no child
            # at all, it will work just as expected. In practice, it's required to
            # have standard file cache work together with redis cache.
            create_span(tracer)
          end
          span = tracer.active_span()
          return unless span

          begin
            # finish the tracing and update the execution time
            span.resource = resource
            span.set_tag('rails.cache.backend', ::Rails.configuration.cache_store)
            span.set_tag('rails.cache.key', payload.fetch(:key))

            if payload[:exception]
              error = payload[:exception]
              span.status = 1
              span.set_tag(Datadog::Ext::Errors::TYPE, error[0])
              span.set_tag(Datadog::Ext::Errors::MSG, error[1])
            end

          ensure
            span.start_time = start
            span.finish_at(finish)
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        private_class_method :create_span, :get_key, :start_trace_cache, :trace_cache
      end
    end
  end
end
