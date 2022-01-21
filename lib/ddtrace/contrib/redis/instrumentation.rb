# typed: false
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/redis/ext'
require 'ddtrace/contrib/redis/configuration/resolver'

module Datadog
  module Contrib
    module Redis
      # Instrumentation for Redis
      module Instrumentation
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def call(*args, &block)
            response = nil
            Datadog::Tracing.trace(Datadog::Contrib::Redis::Ext::SPAN_COMMAND) do |span|
              span.service = Datadog::Tracing.configuration_for(self, :service_name) || datadog_configuration[:service_name]
              span.span_type = Datadog::Contrib::Redis::Ext::TYPE
              span.resource = get_command(args)
              Datadog::Contrib::Redis::Tags.set_common_tags(self, span)

              response = super
            end

            response
          end

          def call_pipeline(*args, &block)
            response = nil
            Datadog::Tracing.trace(Datadog::Contrib::Redis::Ext::SPAN_COMMAND) do |span|
              span.service = Datadog::Tracing.configuration_for(self, :service_name) || datadog_configuration[:service_name]
              span.span_type = Datadog::Contrib::Redis::Ext::TYPE
              commands = get_pipeline_commands(args)
              span.resource = commands.join("\n")
              span.set_metric Datadog::Contrib::Redis::Ext::METRIC_PIPELINE_LEN, commands.length
              Datadog::Contrib::Redis::Tags.set_common_tags(self, span)

              response = super
            end

            response
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
            Datadog::Tracing.configuration[:redis, options]
          end
        end
      end
    end
  end
end
