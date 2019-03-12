module Datadog
  module Contrib
    module Sequel
      # General purpose functions for Sequel
      module Utils
        class << self
          def adapter_name(database)
            Datadog::Utils::Database.normalize_vendor(database.adapter_scheme.to_s)
          end

          def parse_opts(sql, opts, db_opts)
            if ::Sequel::VERSION >= '4.37.0' && !sql.is_a?(String)
              # In 4.37.0, sql was converted to a prepared statement object
              sql = sql.prepared_sql unless sql.is_a?(Symbol)
            end

            {
              name: opts[:type],
              query: sql,
              database: db_opts[:database],
              host: db_opts[:host]
            }
          end

          def set_analytics_sample_rate(span)
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
