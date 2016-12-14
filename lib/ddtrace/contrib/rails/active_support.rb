require 'ddtrace/ext/cache'

module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActiveSupport
        def self.instrument
          # subscribe when a cache read starts being processed
          ::ActiveSupport::Notifications.subscribe('start_cache_read.active_support') do |*args|
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
        end

        def self.start_trace_cache(*)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          type = Datadog::Ext::CACHE::TYPE
          tracer.trace('rails.cache', span_type: type)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.trace_cache(resource, _name, start, finish, _id, payload)
          # finish the tracing and update the execution time
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          span.service = ::Rails.configuration.datadog_trace.fetch(:default_cache_service)
          span.resource = resource
          span.set_tag('rails.cache.backend', ::Rails.configuration.cache_store)
          span.set_tag('rails.cache.key', payload.fetch(:key))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        private_class_method :trace_cache
      end
    end
  end
end
