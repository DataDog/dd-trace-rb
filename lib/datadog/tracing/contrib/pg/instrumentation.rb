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
            def exec(sql, *args)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_EXEC, service: service, resource: sql,
                                            type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, sql, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql, *args)
                annotate_span_with_result!(span, result)
                result
              end
            end

            def exec_params(sql, params, *args)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_EXEC_PARAMS, service: service, resource: sql,
                                                   type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, sql, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql, params, *args)
                annotate_span_with_result!(span, result)
                result
              end
            end

            def async_exec(sql, *args)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_ASYNC_EXEC, service: service, resource: sql,
                                                  type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, sql, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql, *args)
                annotate_span_with_result!(span, result)
                result
              end
            end

            def async_exec_params(sql, params, *args)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_ASYNC_EXEC_PARAMS, service: service, resource: sql,
                                                         type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, sql, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql, params, *args)
                annotate_span_with_result!(span, result)
                result
              end
            end

            def sync_exec(sql, *args)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_SYNC_EXEC, service: service, resource: sql,
                                                 type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, sql, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql, *args)
                annotate_span_with_result!(span, result)
                result
              end
            end

            def sync_exec_params(sql, params, *args)
              service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

              Tracing.trace(Ext::SPAN_SYNC_EXEC_PARAMS, service: service, resource: sql,
                                                        type: Tracing::Metadata::Ext::SQL::TYPE) do |span|
                annotate_span_with_query!(span, sql, service)
                # Set analytics sample rate
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

                result = super(sql, params, *args)
                annotate_span_with_result!(span, result)
                result
              end
            end

            def annotate_span_with_query!(span, sql, service)
              span.set_tag(Ext::TAG_DB_NAME, db)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host)

              span.set_tag(Tracing::Metadata::Ext::DB::TAG_INSTANCE, db)
              span.set_tag(Tracing::Metadata::Ext::DB::TAG_USER, user)
              span.set_tag(Tracing::Metadata::Ext::DB::TAG_SYSTEM, Ext::SPAN_SYSTEM)
              span.set_tag(Tracing::Metadata::Ext::DB::TAG_STATEMENT, sql)

              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, port)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME, host)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT, port)
            end

            def annotate_span_with_result!(span, result)
              row_count = result.ntuples
              span.set_tag(Tracing::Metadata::Ext::DB::TAG_ROW_COUNT, row_count)
              span.set_tag(Tracing::Metadata::Ext::SQL::TAG_ROWS, row_count)
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
