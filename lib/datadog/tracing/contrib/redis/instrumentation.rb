# typed: false

require_relative '../patcher'
require_relative 'configuration/resolver'
require_relative 'ext'
require_relative 'quantize'
require_relative 'tags'

module Datadog
  module Tracing
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
              show_command_args = command_args?

              Tracing.trace(Contrib::Redis::Ext::SPAN_COMMAND) do |span|
                span.service = service_name
                span.span_type = Contrib::Redis::Ext::TYPE
                span.resource = get_command(args, show_command_args)
                Contrib::Redis::Tags.set_common_tags(self, span, show_command_args)

                super
              end
            end

            def call_pipeline(*args, &block)
              show_command_args = command_args?

              Tracing.trace(Contrib::Redis::Ext::SPAN_COMMAND) do |span|
                span.service = service_name
                span.span_type = Contrib::Redis::Ext::TYPE
                commands = get_pipeline_commands(args, show_command_args)
                span.resource = commands.any? ? commands.join("\n") : '(none)'
                span.set_metric Contrib::Redis::Ext::METRIC_PIPELINE_LEN, commands.length
                Contrib::Redis::Tags.set_common_tags(self, span, show_command_args)

                super
              end
            end

            private

            def command_args?
              pinned = Datadog.configuration_for(redis_instance, :command_args)

              return pinned unless pinned.nil?

              datadog_configuration[:command_args]
            end

            def service_name
              Datadog.configuration_for(redis_instance, :service_name) ||
                datadog_configuration[:service_name]
            end

            def get_command(args, show_command_args)
              if show_command_args
                Contrib::Redis::Quantize.format_command_args(*args)
              else
                Contrib::Redis::Quantize.get_verb(*args)
              end
            end

            def get_pipeline_commands(args, show_command_args)
              if show_command_args
                args[0].commands.map { |c| Contrib::Redis::Quantize.format_command_args(c) }
              else
                args[0].commands.map { |c| Contrib::Redis::Quantize.get_verb(c) }
              end
            end

            def datadog_configuration
              Datadog.configuration.tracing[:redis, options]
            end
          end
        end
      end
    end
  end
end
