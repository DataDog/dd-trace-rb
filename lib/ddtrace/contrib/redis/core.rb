require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module Redis
      COMMAND = 'redis.command'.freeze
      ARGS = 'redis.args'.freeze

      DEFAULTSERVICE = 'redis'.freeze
      SPAN_TYPE = 'redis'.freeze

      # Datadog APM Redis integration.
      module TracedRedis
        def initialize(*args)
          pin = Datadog::Pin.new(DEFAULTSERVICE, app: 'redis', app_type: Datadog::Ext::AppTypes::DB)
          pin.onto(self)
          super(*args)
        end

        def get(*args)
          pin = Datadog::Pin.get_from(self)
          response = nil
          tracer = Datadog.tracer
          tracer.trace(pin.name ? pin.name : 'redis.get') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE

            response = super(*args)
          end

          response
        end

        def set(*args)
          pin = Datadog::Pin.get_from(self)
          response = nil
          tracer = Datadog.tracer
          tracer.trace(pin.name ? pin.name : 'redis.set') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE

            response = super(*args)
          end

          response
        end

        def call(*args)
          pin = Datadog::Pin.get_from(self)
          response = nil
          tracer = Datadog.tracer
          tracer.trace(pin.name ? pin.name : 'redis.call') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE

            response = super(*args)
          end

          response
        end

        def execute_commmand(*args)
          pin = Datadog::Pin.get_from(self)
          response = nil
          tracer = Datadog.tracer
          tracer.trace(pin.name ? pin.name : 'redis.command') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE

            response = super(*args)
          end

          response
        end
      end
    end
  end
end
