module Datadog
  module Instrument
    # some stuff
    module RailsFramework
      def self.cache_read(_name, start, finish, _id, payload)
        tracer = Rails.configuration.datadog_trace[:tracer]
        span = tracer.trace('rails.cache')
        span.span_type = 'cache'
        span.resource = 'GET'
        span.set_tag('rails.cache.backend', Rails.configuration.cache_store)
        span.set_tag('rails.cache.key', payload[:key])
        span.start_time = start
        span.finish_at(finish)
      end

      def self.cache_write(_name, start, finish, _id, payload)
        tracer = Rails.configuration.datadog_trace[:tracer]
        span = tracer.trace('rails.cache')
        span.span_type = 'cache'
        span.resource = 'SET'
        span.set_tag('rails.cache.backend', Rails.configuration.cache_store)
        span.set_tag('rails.cache.key', payload[:key])
        span.start_time = start
        span.finish_at(finish)
      end

      def self.cache_delete(_name, start, finish, _id, payload)
        tracer = Rails.configuration.datadog_trace[:tracer]
        span = tracer.trace('rails.cache')
        span.span_type = 'cache'
        span.resource = 'DELETE'
        span.set_tag('rails.cache.backend', Rails.configuration.cache_store)
        span.set_tag('rails.cache.key', payload[:key])
        span.start_time = start
        span.finish_at(finish)
      end
    end
  end
end
