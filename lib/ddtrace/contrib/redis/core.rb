require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/redis/quantize'

module Datadog
  module Contrib
    module Redis
      DEFAULTSERVICE = 'redis'.freeze
      SPAN_TYPE = 'redis'.freeze

      # TracedRedis is a wrapper so that caller can pin on parent object without knowing about client member.
      module TracedRedis
        def datadog_pin=(pin)
          Datadog::Pin.onto(client, pin)
        end

        def datadog_pin
          Datadog::Pin.get_from(client)
        end
      end

      # Datadog APM Redis integration.
      module TracedRedisClient
        def initialize(*args)
          pin = Datadog::Pin.new(DEFAULTSERVICE, app: 'redis', app_type: Datadog::Ext::AppTypes::DB)
          pin.onto(self)
          super(*args)
        end

        def call(*args)
          pin = Datadog::Pin.get_from(self)
          response = nil
          pin.tracer.trace(pin.name ? pin.name : 'redis.command') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE
            span.resource = Datadog::Contrib::Redis::Quantize.format_command_args(*args)

            response = super(*args)
          end

          response
        end
      end
    end
  end
end
