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
          class << self
            include Contrib::Instrumentation

            def base_configuration
              # TODO: how to allow access to instance-level method #hostname here?
              Datadog.configuration[:dalli, "#{hostname}:#{port}"] || Datadog.configuration[:dalli]
            end
          end

          def request(op, *args)
            dd_instrumentation.trace(Datadog::Contrib::Dalli::Ext::SPAN_COMMAND) do |span|
              span.resource = op.to_s.upcase
              span.service = datadog_configuration[:service_name]
              span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
              end

              span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
              span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)

              super
            end
          end

          private

          def dd_instrumentation
            # how do
            singleton_class
          end
        end
      end
    end
  end
end
