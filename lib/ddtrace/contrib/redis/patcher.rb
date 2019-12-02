require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/redis/ext'

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
              pin.tracer.trace(Datadog::Contrib::Redis::Ext::SPAN_COMMAND) do |span|
                span.service = pin.service
                span.span_type = Datadog::Contrib::Redis::Ext::TYPE
                commands = args[0].commands.map { |c| Datadog::Contrib::Redis::Quantize.format_command_args(c) }
                span.resource = commands.join("\n")
                Datadog::Contrib::Redis::Tags.set_common_tags(self, span)
                span.set_metric Datadog::Contrib::Redis::Ext::METRIC_PIPELINE_LEN, commands.length

                response = call_pipeline_without_datadog(*args, &block)
              end

              response
            end

            def datadog_pin
              @datadog_pin ||= begin
                pin = Datadog::Pin.new(
                  Datadog.configuration[:redis][:service_name],
                  app: Ext::APP,
                  app_type: Datadog::Ext::AppTypes::DB,
                  tracer: Datadog.configuration[:redis][:tracer]
                )
                pin.onto(self)
              end
            end
          end
        end
      end
    end
  end
end
