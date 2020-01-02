require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/dalli/ext'
require 'ddtrace/contrib/dalli/quantize'

module Datadog
  module Contrib
    module Dalli
      # Instruments every interaction with the memcached server
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include Contrib::Instrumentation

          def my_configuration
            { name: Datadog.configuration[:dalli, "#{hostname}:#{port}"] || Datadog.configuration[:dalli] }
          end

          def request(op, *args)
            dd_instrumenter.with_configuration(my_configuration) do |instrument|
              instrument.trace(Datadog::Contrib::Dalli::Ext::SPAN_COMMAND) do |span|
                span.resource = op.to_s.upcase
                span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
                end

                span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
                span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
                cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
                span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)

                super
              end
            end
          end

          # TODO: Possible future improvements
          # dd_instrumenter.trace(method(:request)) do |span|
          #  span.name = Datadog::Contrib::Dalli::Ext::SPAN_COMMAND
          #  span.resource = op.to_s.upcase
          #  span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND
          #
          #  # Set analytics sample rate
          #  if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
          #    Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
          #  end
          #
          #  span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
          #  span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
          #  cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
          #  span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)
          #end

          private

          def base_configuration
            Datadog.configuration[:dalli, "#{hostname}:#{port}"] || Datadog.configuration[:dalli]
          end
        end
      end
    end
  end
end
