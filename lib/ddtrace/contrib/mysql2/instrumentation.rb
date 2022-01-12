# typed: false
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/metadata'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/mysql2/ext'

module Datadog
  module Contrib
    module Mysql2
      # Mysql2::Client patch module
      module Instrumentation
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # Mysql2::Client patch instance methods
        module InstanceMethods
          def query(sql, options = {})
            Datadog::Tracing.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE

              span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)

              # Tag as an external peer service
              span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
              span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, query_options[:host])

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              span.set_tag(Ext::TAG_DB_NAME, query_options[:database])
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, query_options[:host])
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, query_options[:port])
              super(sql, options)
            end
          end

          def datadog_pin
            @datadog_pin ||= Datadog::Pin.new(
              Datadog::Tracing.configuration[:mysql2][:service_name],
              app: Ext::TAG_COMPONENT,
              app_type: Datadog::Ext::AppTypes::DB,
            )
          end

          private

          def datadog_configuration
            Datadog::Tracing.configuration[:mysql2]
          end

          def analytics_enabled?
            datadog_configuration[:analytics_enabled]
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
