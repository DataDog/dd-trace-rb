require 'ddtrace/ext/integration'

module Datadog
  module Contrib
    module Sequel
      # General purpose functions for Sequel
      module Utils
        class << self
          # Ruby database connector library
          #
          # e.g. adapter:mysql2 (database:mysql), adapter:jdbc (database:postgres)
          def adapter_name(database)
            scheme = database.adapter_scheme.to_s

            if scheme == 'jdbc'.freeze
              # The subtype is more important in this case,
              # otherwise all database adapters will be 'jdbc'.
              database_type(database)
            else
              Datadog::Utils::Database.normalize_vendor(scheme)
            end
          end

          # Database engine
          #
          # e.g. database:mysql (adapter:mysql2), database:postgres (adapter:jdbc)
          def database_type(database)
            Datadog::Utils::Database.normalize_vendor(database.database_type.to_s)
          end

          def parse_opts(sql, opts, db_opts, dataset = nil)
            # Prepared statements don't provide their sql query in the +sql+ parameter.
            unless sql.is_a?(String)
              if dataset && dataset.respond_to?(:prepared_sql) && (resolved_sql = dataset.prepared_sql)
                # The dataset contains the resolved SQL query and prepared statement name.
                prepared_name = dataset.prepared_statement_name
                sql = resolved_sql
              end
            end

            {
              name: opts[:type],
              query: sql,
              prepared_name: prepared_name,
              database: db_opts[:database],
              host: db_opts[:host]
            }
          end

          def set_common_tags(span)
            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
          end

          private

          def datadog_configuration
            Datadog.configuration[:sequel]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
