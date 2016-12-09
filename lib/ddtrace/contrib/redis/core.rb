require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module Redis
      # Redis integration.
      module TracedRedis
        def get(*args)
          response = nil
          tracer = Datadog.tracer
          tracer.trace('redis.get') do |span|
            span.service = 'FIXME'
            span.span_type = Datadog::Ext::AppTypes::DB

            response = super(*args)
          end

          response
        end

        def set(*args)
          response = nil
          tracer = Datadog.tracer
          tracer.trace('redis.set') do |span|
            span.service = 'FIXME'
            span.span_type = Datadog::Ext::AppTypes::DB

            response = super(*args)
          end

          response
        end

        def call(*args)
          response = nil
          tracer = Datadog.tracer
          tracer.trace('redis.call') do |span|
            span.service = 'FIXME'
            span.span_type = Datadog::Ext::AppTypes::DB

            response = super(*args)
          end

          response
        end
      end
    end
  end
end

# Auto-patching of Redis with our tracing wrappers.
class Redis
  prepend Datadog::Contrib::Redis::TracedRedis
end
