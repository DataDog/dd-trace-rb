require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/redis/tags'
require 'ddtrace/contrib/redis/quantize'

module Datadog
  module Contrib
    module Redis
      SERVICE = 'redis'.freeze

      DRIVER = 'redis.driver'.freeze

      # TracedRedis is a wrapper so that caller can pin on parent object without knowing about client member.
      module TracedRedis
        def datadog_pin=(pin)
          # Forward the pin to client, which actually traces calls.
          Datadog::Pin.onto(client, pin)
        end

        def datadog_pin
          # Get the pin from client, which actually traces calls.
          Datadog::Pin.get_from(client)
        end
      end

      # Datadog APM Redis integration.
      module TracedRedisClient
        def initialize(*args)
          pin = Datadog::Pin.new(SERVICE, app: 'redis', app_type: Datadog::Ext::AppTypes::DB)
          pin.onto(self)
          super(*args)
        end

        def call(*args)
          pin = Datadog::Pin.get_from(self)
          return super(*args) unless pin

          response = nil
          pin.tracer.trace('redis.command') do |span|
            span.service = pin.service
            span.span_type = Datadog::Ext::Redis::TYPE
            span.resource = Datadog::Contrib::Redis::Quantize.format_command_args(*args)
            span.set_tag(Datadog::Ext::Redis::RAWCMD, span.resource)
            Datadog::Contrib::Redis::Tags.set_common_tags(self, span)

            response = super(*args)
          end

          response
        end

        def call_pipeline(*args)
          pin = Datadog::Pin.get_from(self)
          return super(*args) unless pin

          response = nil
          pin.tracer.trace('redis.command') do |span|
            span.service = pin.service
            span.span_type = Datadog::Ext::Redis::TYPE
            commands = args[0].commands.map { |c| Datadog::Contrib::Redis::Quantize.format_command_args(c) }
            span.resource = commands.join("\n")
            span.set_tag(Datadog::Ext::Redis::RAWCMD, span.resource)
            Datadog::Contrib::Redis::Tags.set_common_tags(self, span)

            response = super(*args)
          end

          response
        end

        def connect(*args)
          pin = Datadog::Pin.get_from(self)
          return super(*args) unless pin

          response = nil
          pin.tracer.trace(pin.name ? pin.name : 'redis.connect') do |span|
            span.service = pin.service
            span.span_type = Datadog::Ext::Redis::TYPE
            span.resource = "#{host}:#{port}:#{db}"
            Datadog::Contrib::Redis::Tags.set_common_tags(self, span)
            span.set_tag DRIVER, driver

            response = super(*args)
          end

          response
        end
      end
    end
  end
end
