# typed: true

require_relative '../patcher'
require_relative 'instrumentation'

module Datadog
  module Tracing
    module Contrib
      module Mysql2
        # Patcher enables patching of 'mysql2' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            patch_mysql2_client
          end

          def patch_mysql2_client
            # ::Mysql2::Client.include(Instrumentation)

            Datadog::Tracing.trace_method('Mysql2::Client#query', Ext::SPAN_QUERY).around do |env, span, _trace, &block|
              sql = env.args[0]
              query_options = env.self.query_options

              service = Datadog.configuration_for(env.self, :service_name) || datadog_configuration[:service_name]
              span.service = service

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

              block.call
            end
          end

          def datadog_configuration
            Datadog.configuration.tracing[:mysql2]
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
