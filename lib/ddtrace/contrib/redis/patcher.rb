# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module Redis
      SERVICE = 'redis'.freeze
      DRIVER = 'redis.driver'.freeze

      # Patcher enables patching of 'redis' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        include Base
        register_as :redis, auto_patch: true
        option :service_name, default: SERVICE

        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          if !@patched && (defined?(::Redis::VERSION) && \
                           Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('3.0.0'))
            begin
              # do not require these by default, but only when actually patching
              require 'ddtrace/monkey'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/contrib/redis/tags'
              require 'ddtrace/contrib/redis/quantize'

              patch_redis()
              patch_redis_client()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Redis integration: #{e}")
            end
          end
          @patched
        end

        def patch_redis
          ::Redis.module_eval do
            def datadog_pin=(pin)
              # Forward the pin to client, which actually traces calls.
              Datadog::Pin.onto(client, pin)
            end

            def datadog_pin
              # Get the pin from client, which actually traces calls.
              Datadog::Pin.get_from(client)
            end
          end
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        def patch_redis_client
          ::Redis::Client.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Monkey.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              service = Datadog.configuration[:redis][:service_name]
              pin = Datadog::Pin.new(service, app: 'redis', app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              if pin.tracer && pin.service
                pin.tracer.set_service_info(pin.service, pin.app, pin.app_type)
              end
              initialize_without_datadog(*args)
            end

            alias_method :call_without_datadog, :call
            remove_method :call
            def call(*args, &block)
              pin = Datadog::Pin.get_from(self)
              return call_without_datadog(*args, &block) unless pin && pin.tracer

              response = nil
              pin.tracer.trace('redis.command') do |span|
                span.service = pin.service
                span.span_type = Datadog::Ext::Redis::TYPE
                span.resource = Datadog::Contrib::Redis::Quantize.format_command_args(*args)
                Datadog::Contrib::Redis::Tags.set_common_tags(self, span)

                response = call_without_datadog(*args, &block)
              end

              response
            end

            alias_method :call_pipeline_without_datadog, :call_pipeline
            remove_method :call_pipeline
            def call_pipeline(*args, &block)
              pin = Datadog::Pin.get_from(self)
              return call_pipeline_without_datadog(*args, &block) unless pin && pin.tracer

              response = nil
              pin.tracer.trace('redis.command') do |span|
                span.service = pin.service
                span.span_type = Datadog::Ext::Redis::TYPE
                commands = args[0].commands.map { |c| Datadog::Contrib::Redis::Quantize.format_command_args(c) }
                span.resource = commands.join("\n")
                Datadog::Contrib::Redis::Tags.set_common_tags(self, span)
                span.set_metric Datadog::Ext::Redis::PIPELINE_LEN, commands.length

                response = call_pipeline_without_datadog(*args, &block)
              end

              response
            end
          end
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
