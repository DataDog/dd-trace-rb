# typed: false

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/pg/ext'

module Datadog
  module Tracing
    module Contrib
      module Pg
        # PG::Connection patch module
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # PG::Connection patch methods
          module InstanceMethods
            def exec(sql)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_EXEC, service: service) do |span|
                span.resource = sql
                span.type = Tracing::Metadata::Ext::SQL::TYPE
                span.service = Ext::DEFAULT_PEER_SERVICE_NAME

                span.set_tag('db.instance', db)
                span.set_tag('db.user', user)
                span.set_tag('db.system', Ext::SPAN_SYSTEM)
                span.set_tag('db.statement', sql)

                span.set_tag('network.destination.name', host)
                span.set_tag('network.destination.port', port)

                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)

                span.set_tag(Ext::TAG_DB_NAME, db)

                # Tag as an external peer service
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, service)
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host)
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host)
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, port)

                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql)
                span.set_tag('db.row_count', result.ntuples)
                span.set_tag('sql.rows', result.ntuples)
                result
              end
            end

            private

            def datadog_configuration
              Datadog.configuration.tracing[:pg]
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
end
