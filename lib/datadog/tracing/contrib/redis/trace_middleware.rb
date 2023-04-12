require_relative '../patcher'
require_relative 'ext'
require_relative 'quantize'
require_relative 'tags'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Instrumentation for Redis 5+
        module TraceMiddleware
          def call(commands, redis_config)
            Tracing.trace(Contrib::Redis::Ext::SPAN_COMMAND) do |span|
              datadog_configuration = resolve(redis_config)
              resource = get_command(commands, datadog_configuration[:command_args])

              span.service = datadog_configuration[:service_name]
              span.span_type = Contrib::Redis::Ext::TYPE
              span.resource = resource

              Contrib::Redis::Tags.set_common_tags(redis_config, span, datadog_configuration[:command_args])

              super
            end
          end

          def call_pipelined(commands, redis_config)
            Tracing.trace(Contrib::Redis::Ext::SPAN_COMMAND) do |span|
              datadog_configuration = resolve(redis_config)
              pipelined_commands = get_pipeline_commands(commands, datadog_configuration[:command_args])

              span.service = datadog_configuration[:service_name]
              span.span_type = Contrib::Redis::Ext::TYPE
              span.resource = pipelined_commands.join("\n")
              span.set_metric Contrib::Redis::Ext::METRIC_PIPELINE_LEN, pipelined_commands.length

              Contrib::Redis::Tags.set_common_tags(redis_config, span, datadog_configuration[:command_args])

              super
            end
          end

          private

          def get_command(commands, boolean)
            if boolean
              Contrib::Redis::Quantize.format_command_args(commands)
            else
              Contrib::Redis::Quantize.get_verb(commands)
            end
          end

          def get_pipeline_commands(commands, boolean)
            if boolean
              commands.map { |c| Contrib::Redis::Quantize.format_command_args(c) }
            else
              commands.map { |c| Contrib::Redis::Quantize.get_verb(c) }
            end
          end

          def resolve(redis_config)
            custom = redis_config.custom[:datadog] || {}

            Datadog.configuration.tracing[:redis, redis_config.server_url].to_h.merge(custom)
          end
        end
      end
    end
  end
end
