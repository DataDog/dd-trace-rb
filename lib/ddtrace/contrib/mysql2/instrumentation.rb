require 'ddtrace/ext/app_types'
require 'ddtrace/ext/integration'
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
          base.send(:prepend, InstanceMethods)
        end

        # Mysql2::Client patch instance methods
        module InstanceMethods
          def query(sql, options = {})
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE

              # Tag as an external peer service
              span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

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
              Datadog.configuration[:mysql2][:service_name],
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::DB,
              tracer: -> { Datadog.configuration[:mysql2][:tracer] }
            )
          end

          private

          def datadog_configuration
            Datadog.configuration[:mysql2]
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
