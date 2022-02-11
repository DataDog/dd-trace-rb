# typed: false
require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/mysql2/ext'

module Datadog
  module Tracing
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
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_QUERY, service: service) do |span|
                span.resource = sql
                span.span_type = Tracing::Metadata::Ext::SQL::TYPE

                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)

                # Tag as an external peer service
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, service)
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, query_options[:host])

                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                span.set_tag(Ext::TAG_DB_NAME, query_options[:database])
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, query_options[:host])
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, query_options[:port])
                super(sql, options)
              end
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
end
