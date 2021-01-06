require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/redis/ext'
require 'ddtrace/contrib/redis/configuration/resolver'

module Datadog
  module Contrib
    module Redis
      # Patcher enables patching of 'redis' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        # patch applies our patch if needed
        def patch
          # do not require these by default, but only when actually patching
          require 'redis'
          require 'ddtrace/ext/app_types'
          require 'ddtrace/contrib/redis/tags'
          require 'ddtrace/contrib/redis/quantize'

          patch_redis_client
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        # rubocop:disable Metrics/AbcSize
        def patch_redis_client
          ::Redis::Client.class_eval do
            alias_method :call_without_datadog, :call
            remove_method :call
            def call(*args, &block)
              pin = Datadog::Pin.get_from(self)
              return call_without_datadog(*args, &block) unless pin && pin.tracer

              response = nil
              pin.tracer.trace(Datadog::Contrib::Redis::Ext::SPAN_COMMAND) do |span|
                span.service = pin.service
                span.span_type = Datadog::Contrib::Redis::Ext::TYPE
                span.resource = get_command(args)
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
              pin.tracer.trace(Datadog::Contrib::Redis::Ext::SPAN_COMMAND) do |span|
                span.service = pin.service
                span.span_type = Datadog::Contrib::Redis::Ext::TYPE
                commands = get_pipeline_commands(args)
                span.resource = commands.join("\n")
                span.set_metric Datadog::Contrib::Redis::Ext::METRIC_PIPELINE_LEN, commands.length
                Datadog::Contrib::Redis::Tags.set_common_tags(self, span)

                response = call_pipeline_without_datadog(*args, &block)
              end

              response
            end

            def datadog_pin
              @datadog_pin ||= begin
                pin = Datadog::Pin.new(
                  datadog_configuration[:service_name],
                  app: Ext::APP,
                  app_type: Datadog::Ext::AppTypes::DB,
                  tracer: -> { datadog_configuration[:tracer] }
                )
                pin.onto(self)
              end
            end

            private

            def get_command(args)
              if datadog_configuration[:command_args]
                Datadog::Contrib::Redis::Quantize.format_command_args(*args)
              else
                Datadog::Contrib::Redis::Quantize.get_verb(*args)
              end
            end

            def get_pipeline_commands(args)
              if datadog_configuration[:command_args]
                args[0].commands.map { |c| Datadog::Contrib::Redis::Quantize.format_command_args(c) }
              else
                args[0].commands.map { |c| Datadog::Contrib::Redis::Quantize.get_verb(c) }
              end
            end

            def datadog_configuration
              Datadog.configuration[:redis, options]
            end
          end
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/BlockLength
      end
    end
  end
end
