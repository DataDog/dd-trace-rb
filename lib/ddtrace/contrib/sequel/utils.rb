module Datadog
  module Contrib
    module Sequel
      # General purpose functions for Sequel
      module Utils
        module_function

        def adapter_name(database)
          Datadog::Utils::Database.normalize_vendor(database.adapter_scheme.to_s)
        end

        def parse_opts(sql, opts, db_opts)
          if ::Sequel::VERSION > '4.36.0' && !sql.is_a?(String)
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
      end
    end
  end
end
