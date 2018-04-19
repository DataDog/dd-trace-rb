module Datadog
  module Contrib
    module Sequel
      # General purpose functions for Sequel
      module Utils
        def adapter_name
          Datadog::Utils::Database.normalize_vendor(db.adapter_scheme.to_s)
        end

        def parse_opts(sql, opts)
          db_opts = if ::Sequel::VERSION < '3.41.0' && self.class.to_s !~ /Dataset$/
                      @opts
                    elsif instance_variable_defined?(:@pool) && @pool
                      @pool.db.opts
                    else
                      @db.opts
                    end

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
