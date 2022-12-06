# typed: false

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative '../ext'
require_relative 'ext'

require_relative '../propagation/sql_comment'
require_relative '../propagation/sql_comment/mode'

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
              trace(Ext::SPAN_EXEC, sql: sql) do |sql_statement|
                super(sql_statement, *args)
              end
            end

            def exec_params(sql, params, *args)
              trace(Ext::SPAN_EXEC_PARAMS, sql: sql) do |sql_statement|
                super(sql_statement, params, *args)
              end
            end

            def exec_prepared(statement_name, params, *args)
              trace(Ext::SPAN_EXEC_PREPARED, statement_name: statement_name) do
                super(statement_name, params, *args)
              end
            end

            def async_exec(sql, *args)
              trace(Ext::SPAN_ASYNC_EXEC, sql: sql) do |sql_statement|
                super(sql_statement, *args)
              end
            end

            def async_exec_params(sql, params, *args)
              trace(Ext::SPAN_ASYNC_EXEC_PARAMS, sql: sql) do |sql_statement|
                super(sql_statement, params, *args)
              end
            end

            def async_exec_prepared(statement_name, params, *args)
              trace(Ext::SPAN_ASYNC_EXEC_PREPARED, statement_name: statement_name) do
                super(statement_name, params, *args)
              end
            end

            def sync_exec(sql, *args)
              trace(Ext::SPAN_SYNC_EXEC, sql: sql) do |sql_statement|
                super(sql_statement, *args)
              end
            end

            def sync_exec_params(sql, params, *args)
              trace(Ext::SPAN_SYNC_EXEC_PARAMS, sql: sql) do |sql_statement|
                super(sql_statement, params, *args)
              end
            end

            def sync_exec_prepared(statement_name, params, *args)
              trace(Ext::SPAN_SYNC_EXEC_PREPARED, statement_name: statement_name) do
                super(statement_name, params, *args)
              end
            end

            private

            def trace(name, sql: nil, statement_name: nil)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]
              resource = statement_name || sql

              Tracing.trace(
                name,
                service: service,
                resource: resource,
                type: Tracing::Metadata::Ext::SQL::TYPE
              ) do |span, trace_op|
                annotate_span_with_query!(span, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                if sql
                  propagation_mode = Contrib::Propagation::SqlComment::Mode.new(comment_propagation)
                  Contrib::Propagation::SqlComment.annotate!(span, propagation_mode)
                  propagated_sql_statement = Contrib::Propagation::SqlComment.prepend_comment(
                    sql,
                    span,
                    trace_op,
                    propagation_mode
                  )
                end

                result = yield(propagated_sql_statement)
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
              span.set_tag(Contrib::Ext::DB::TAG_SYSTEM, Ext::TAG_SYSTEM)

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

            def comment_propagation
              datadog_configuration[:comment_propagation]
            end
          end
        end
      end
    end
  end
end
