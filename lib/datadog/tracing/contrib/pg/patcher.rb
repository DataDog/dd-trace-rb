# typed: ignore

require_relative '../patcher'

module Datadog
  module Tracing
    module Contrib
      module Pg
        # Patcher enables patching of 'pg' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            patch_pg_connection
          end

          def patch_pg_connection
            # ::PG::Connection.include(Instrumentation)

            instrumentation_points = [
              [Ext::SPAN_EXEC, 'PG::Connection#exec'],
              [Ext::SPAN_EXEC_PARAMS, 'PG::Connection#exec_params'],
              [Ext::SPAN_EXEC_PREPARED, 'PG::Connection#exec_prepared'],
              [Ext::SPAN_ASYNC_EXEC, 'PG::Connection#async_exec'],
              [Ext::SPAN_ASYNC_EXEC_PARAMS, 'PG::Connection#async_exec_params'],
              [Ext::SPAN_ASYNC_EXEC_PREPARED, 'PG::Connection#async_exec_prepared'],
              [Ext::SPAN_SYNC_EXEC, 'PG::Connection#sync_exec'],
              [Ext::SPAN_SYNC_EXEC_PARAMS, 'PG::Connection#sync_exec_params'],
              [Ext::SPAN_SYNC_EXEC_PREPARED, 'PG::Connection#sync_exec_prepared']
            ]

            instrumentation_points.each do |name, target|
              Datadog::Tracing.trace_method(
                target,
                name,
                { type: Tracing::Metadata::Ext::SQL::TYPE }
              ).around do |env, span, _trace, &block|
                service = Datadog.configuration_for(env.self, :service_name) || datadog_configuration[:service_name]
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
                annotate_span_with_query!(span, env, service, env.args.first)
                result = block.call
                annotate_span_with_result!(span, result)
                result
              end
            end
          end

          def annotate_span_with_query!(span, env, service, resource)
            span.service = service
            span.resource = resource

            span.set_tag(Ext::TAG_DB_NAME, env.self.db)

            span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)
            span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

            # Tag as an external peer service
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, service)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, env.self.host)

            span.set_tag(Tracing::Metadata::Ext::DB::TAG_INSTANCE, env.self.db)
            span.set_tag(Tracing::Metadata::Ext::DB::TAG_USER, env.self.user)
            span.set_tag(Tracing::Metadata::Ext::DB::TAG_SYSTEM, Ext::SPAN_SYSTEM)

            span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, env.self.host)
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, env.self.port)
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME, env.self.host)
            span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT, env.self.port)
          end

          def annotate_span_with_result!(span, result)
            span.set_tag(Tracing::Metadata::Ext::DB::TAG_ROW_COUNT, result.ntuples)
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
