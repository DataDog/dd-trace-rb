# typed: false
require 'ddtrace/ext/metadata'
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
          base.prepend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def request(op, *args)
            tracer.trace(Datadog::Contrib::Dalli::Ext::SPAN_COMMAND) do |span|
              span.resource = op.to_s.upcase
              span.service = datadog_configuration[:service_name]
              span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

              span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_COMMAND)

              # Tag as an external peer service
              span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
              span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, hostname)

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
            Datadog.tracer
          end

          def datadog_configuration
            Datadog::Tracing.configuration[:dalli, "#{hostname}:#{port}"] || Datadog::Tracing.configuration[:dalli]
          end
        end
      end
    end
  end
end
