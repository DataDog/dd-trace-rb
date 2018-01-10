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
        option :tracer, default: Datadog.tracer

        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          if !@patched && compatible?
            begin
              # do not require these by default, but only when actually patching
              require 'ddtrace/monkey'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/contrib/redis/tags'
              require 'ddtrace/contrib/redis/quantize'

              redis_version_4_plus? ? patch_redis_4_plus : patch_redis_3
              patch_redis_client
              @patched = true
              RailsCachePatcher.reload_cache_store if Datadog.registry[:rails].patched?
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Redis integration: #{e}")
            end
          end
          @patched
        end

        def redis_version_4_plus?
          defined?(::Redis::VERSION) && Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('4.0.0')
        end

        def compatible?
          defined?(::Redis::VERSION) && Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('3.0.0')
        end

        def patch_redis_3
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

        # Redis changed the backwards compatibility of #client for version 4+
        # See https://github.com/redis/redis-rb/commit/c239abb43c2dce99468bf94652a3c48b31a1041a
        #     https://github.com/redis/redis-rb/commit/31385074b6bbeef7e1f9849b0b1149b9ef870e2d
        def patch_redis_4_plus
          ::Redis.module_eval do
            def datadog_pin=(pin)
              # Forward the pin to client, which actually traces calls.
              Datadog::Pin.onto(_client, pin)
            end

            def datadog_pin
              # Get the pin from client, which actually traces calls.
              Datadog::Pin.get_from(_client)
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
              tracer = Datadog.configuration[:redis][:tracer]
              pin = Datadog::Pin.new(service, app: 'redis', app_type: Datadog::Ext::AppTypes::DB, tracer: tracer)
              pin.onto(self)
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
