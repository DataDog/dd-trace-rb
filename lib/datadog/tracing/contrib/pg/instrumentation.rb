# typed: false

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative '../ext'
require_relative 'ext'

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
            def exec(sql, *args)
              trace(Ext::SPAN_EXEC, resource: sql) do
                super(sql, *args)
              end
            end

            def exec_params(sql, params, *args)
              trace(Ext::SPAN_EXEC_PARAMS, resource: sql) do
                super(sql, params, *args)
              end
            end

            def exec_prepared(statement_name, params, *args)
              trace(Ext::SPAN_EXEC_PREPARED, resource: statement_name) do
                super(statement_name, params, *args)
              end
            end

            def async_exec(sql, *args)
              trace(Ext::SPAN_ASYNC_EXEC, resource: sql) do
                super(sql, *args)
              end
            end

            def async_exec_params(sql, params, *args)
              trace(Ext::SPAN_ASYNC_EXEC_PARAMS, resource: sql) do
                super(sql, params, *args)
              end
            end

            def async_exec_prepared(statement_name, params, *args)
              trace(Ext::SPAN_ASYNC_EXEC_PREPARED, resource: statement_name) do
                super(statement_name, params, *args)
              end
            end

            def sync_exec(sql, *args)
              trace(Ext::SPAN_SYNC_EXEC, resource: sql) do
                super(sql, *args)
              end
            end

            def sync_exec_params(sql, params, *args)
              trace(Ext::SPAN_SYNC_EXEC_PARAMS, resource: sql) do
                super(sql, params, *args)
              end
            end

            def sync_exec_prepared(statement_name, params, *args)
              trace(Ext::SPAN_SYNC_EXEC_PREPARED, resource: statement_name) do
                super(statement_name, params, *args)
              end
            end

            private

            def trace(name, resource:)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]
              Tracing.trace(name, service: service, resource: resource, type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
                result = yield
                annotate_span_with_result!(span, result)
                result
              end
            end

            def annotate_span_with_query!(span, service)
              span.set_tag(Ext::TAG_DB_NAME, db)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)
              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host)

              span.set_tag(Contrib::Ext::DB::TAG_INSTANCE, db)
              span.set_tag(Contrib::Ext::DB::TAG_USER, user)
              span.set_tag(Contrib::Ext::DB::TAG_SYSTEM, Contrib::Ext::DB::POSTGRESQL)

              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, port)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME, host)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT, port)
            end

            def annotate_span_with_result!(span, result)
              span.set_tag(Contrib::Ext::DB::TAG_ROW_COUNT, result.ntuples)
            end

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
