module Datadog
  module Contrib
    module Sequel
      # TODO[manu]: write docs
      module Utils
        def adapter_name
          @adapter_name ||= Datadog::Contrib::Rails::Utils.normalize_vendor(
            db.adapter_scheme.to_s
          )
        end

        def sanitize_sql(sql)
          regexp = Regexp.new('(\'[\s\S][^\']*\'|\d*\.\d+|\d+|NULL)', Regexp::IGNORECASE)
          sql.to_s.gsub(regexp, '?')
        end

        def parse_opts(sql, opts)
          db_opts = if ::Sequel::VERSION < '3.41.0' && self.class.to_s !~ /Dataset$/
                      @opts
                    elsif @pool
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
            query: sanitize_sql(sql),
            database: db_opts[:database],
            host: db_opts[:host]
          }
        end
      end
    end
  end
end
