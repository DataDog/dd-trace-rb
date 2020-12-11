require 'ddtrace/ext/integration'
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
          def request(op, *args)
            tracer.trace(Datadog::Contrib::Dalli::Ext::SPAN_COMMAND) do |span|
              span.resource = op.to_s.upcase
              span.service = datadog_configuration[:service_name]
              span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

              # Tag as an external peer service
              span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

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

          def tracer
            datadog_configuration[:tracer]
          end

          def datadog_configuration
            Datadog.configuration[:dalli, "#{hostname}:#{port}"] || Datadog.configuration[:dalli]
          end
        end
      end
    end
  end
end
