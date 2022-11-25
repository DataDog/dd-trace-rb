# typed: false

require_relative '../patcher'
# require_relative 'configuration/resolver'
require_relative 'ext'
require_relative 'quantize'
require_relative 'tags'
require_relative 'vendor/resolver'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Instrumentation for Redis
        module TraceMiddleware
          def call(*args, redis_config)
            datadog_configuration = resolve(redis_config)

            Tracing.trace(Contrib::Redis::Ext::SPAN_COMMAND) do |span|
              span.service = datadog_configuration[:service_name]
              span.span_type = Contrib::Redis::Ext::TYPE

              span.resource = get_command(args, datadog_configuration[:command_args])
              Contrib::Redis::Tags.set_common_tags(redis_config, span, datadog_configuration[:command_args])

              super
            end
          end

          def call_pipelined(args, redis_config)
            datadog_configuration = resolve(redis_config)

            Tracing.trace(Contrib::Redis::Ext::SPAN_COMMAND) do |span|
              span.service = datadog_configuration[:service_name]
              span.span_type = Contrib::Redis::Ext::TYPE

              commands = get_pipeline_commands(args, datadog_configuration[:command_args])
              span.resource = commands.join("\n")
              span.set_metric Contrib::Redis::Ext::METRIC_PIPELINE_LEN, commands.length
              Contrib::Redis::Tags.set_common_tags(redis_config, span, datadog_configuration[:command_args])

              super
            end
          end

          private

          def get_command(args, boolean)
            if boolean
              Contrib::Redis::Quantize.format_command_args(*args)
            else
              Contrib::Redis::Quantize.get_verb(*args)
            end
          end

          def get_pipeline_commands(args, boolean)
            if boolean
              args.map { |c| Contrib::Redis::Quantize.format_command_args(c) }
            else
              args.map { |c| Contrib::Redis::Quantize.get_verb(c) }
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
