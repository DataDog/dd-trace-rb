module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActiveSupport
        def self.instrument
          # subscribe when a cache read has been processed
          ::ActiveSupport::Notifications.subscribe('cache_read.active_support') do |*args|
            cache_read(*args)
          end

          # subscribe when a cache write has been processed
          ::ActiveSupport::Notifications.subscribe('cache_write.active_support') do |*args|
            cache_write(*args)
          end

          # subscribe when a cache delete has been processed
          ::ActiveSupport::Notifications.subscribe('cache_delete.active_support') do |*args|
            cache_delete(*args)
          end
        end

        def self.cache_read(_name, start, finish, _id, payload)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.trace('rails.cache')
          span.span_type = 'cache'
          span.resource = 'GET'
          span.set_tag('rails.cache.backend', ::Rails.configuration.cache_store)
          span.set_tag('rails.cache.key', payload.fetch(:key))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end

        def self.cache_write(_name, start, finish, _id, payload)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.trace('rails.cache')
          span.span_type = 'cache'
          span.resource = 'SET'
          span.set_tag('rails.cache.backend', ::Rails.configuration.cache_store)
          span.set_tag('rails.cache.key', payload.fetch(:key))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end

        def self.cache_delete(_name, start, finish, _id, payload)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.trace('rails.cache')
          span.span_type = 'cache'
          span.resource = 'DELETE'
          span.set_tag('rails.cache.backend', ::Rails.configuration.cache_store)
          span.set_tag('rails.cache.key', payload.fetch(:key))
          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          # TODO[manu]: better error handling
          puts e
        end
      end
    end
  end
end
