# frozen_string_literal: true

require_relative "../../metadata/ext"
require_relative "../utils/database"
require_relative "ext"
require_relative "jdbc_connection_string"
require_relative "../ext"
require_relative "../span_attribute_schema"

module Datadog
  module Tracing
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

              if scheme == "jdbc"
                # The subtype is more important in this case,
                # otherwise all database adapters will be 'jdbc'.
                database_type(database)
              else
                Contrib::Utils::Database.normalize_vendor(scheme)
              end
            end

            # Database engine
            #
            # e.g. database:mysql (adapter:mysql2), database:postgres (adapter:jdbc)
            def database_type(database)
              Contrib::Utils::Database.normalize_vendor(database.database_type.to_s)
            end

            def parse_opts(sql, opts, db_opts, dataset = nil)
              # Prepared statements don't provide their sql query in the +sql+ parameter.
              if !sql.is_a?(String) && dataset&.respond_to?(:prepared_sql) &&
                  (resolved_sql = dataset.prepared_sql)
                # The dataset contains the resolved SQL query and prepared statement name.
                prepared_name = dataset.prepared_statement_name
                sql = resolved_sql
              end

              {
                name: opts[:type],
                query: sql,
                prepared_name: prepared_name,
                database: db_opts[:database],
                host: db_opts[:host],
              }
            end

            def set_common_tags(span, db)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)
              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
              span.set_tag(Contrib::Ext::DB::TAG_SYSTEM, database_type(db))

              metadata = connection_metadata(db)

              peer_metadata = false

              # Embedded/hostless databases (e.g. SQLite) have no network peer; skip peer-identifying tags.
              if metadata[:host] && !metadata[:host].empty?
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME, metadata[:host])
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, metadata[:host])
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, metadata[:host])
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, metadata[:port]) if metadata[:port]
                peer_metadata = true
              end

              if metadata[:database] && !metadata[:database].empty?
                span.set_tag(Contrib::Ext::DB::TAG_INSTANCE, metadata[:database])
                span.set_tag(Ext::TAG_DB_NAME, metadata[:database])
                peer_metadata = true
              end

              if peer_metadata
                Contrib::SpanAttributeSchema.set_peer_service!(span, Ext::PEER_SERVICE_SOURCES)
              end

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
            end

            # Resolves the connection host/port/database for a Sequel::Database. For Sequel's
            # JDBC adapter (used on JRuby), metadata is parsed from the JDBC connection string
            # regardless of whether opts[:host] is set.
            def connection_metadata(db)
              opts = db.opts || {}
              host = opts[:host]
              port = opts[:port]
              database = opts[:database]

              # A JDBC connection string (in :uri, :url, or :database) can carry credentials, so
              # always emit only parsed metadata -- never the raw connection string.
              connection_string = opts[:uri] || opts[:url] || opts[:database]
              is_jdbc = connection_string.is_a?(String) &&
                connection_string.byteslice(0, 5)&.casecmp("jdbc:") == 0
              if is_jdbc
                parsed = JDBCConnectionString.parse(connection_string)

                # JNDI/DataSource-managed connections keep only a lookup name in opts (e.g.
                # "jdbc:jndi:..."), so nothing can be parsed from it. Recover the endpoint from the
                # live connection's JDBC metadata, the same way Sequel resolves JNDI. This stays a
                # fallback rather than the primary source: it requires a connection checkout and
                # some drivers report no connection string, whereas the opts value is free and
                # already present for direct connections (and non-JDBC adapters have no such
                # metadata at all).
                if parsed[:host].nil? && parsed[:port].nil? && parsed[:database].nil?
                  fallback_metadata = jdbc_metadata_from_connection(db)
                  parsed = fallback_metadata if fallback_metadata
                end

                # Sequel's JDBC adapter connects with the connection string and ignores separate
                # :host/:port options, unlike native adapters where those options take precedence.
                if parsed[:host] || parsed[:port] || parsed[:database]
                  host = parsed[:host]
                  port = parsed[:port]
                end
                database = parsed[:database]
              end

              {host: host, port: port&.to_s, database: database}
            end

            private

            # Resolves host/port/database from the live connection's JDBC metadata
            # (java.sql.DatabaseMetaData#getURL), for JNDI/DataSource connections whose opts hold
            # only a lookup name. Returns the parsed metadata, or nil when it can't be resolved.
            #
            # Only *parsed, credential-free* metadata is memoized -- the raw connection string is
            # used transiently and never stored or logged. A completed lookup that yields no usable
            # connection string is a permanent property of the connection, so it is cached to avoid
            # re-checking out a connection on every query. A raised error is treated as transient
            # (pool checkout timeout, dropped connection, ...) and left uncached, so a later query
            # can retry once connectivity recovers.
            def jdbc_metadata_from_connection(db)
              return db.instance_variable_get(:@datadog_jdbc_metadata) if db.instance_variable_defined?(:@datadog_jdbc_metadata)

              connection_string =
                begin
                  db.synchronize do |conn|
                    conn.get_meta_data.get_url if conn.respond_to?(:get_meta_data)
                  end
                rescue => e
                  Datadog.logger.debug { "Sequel: unable to resolve JDBC connection metadata (#{e.class})" }
                  return nil
                end

              metadata = connection_string && JDBCConnectionString.parse(connection_string)
              db.instance_variable_set(:@datadog_jdbc_metadata, metadata)
              metadata
            end

            def datadog_configuration
              Datadog.configuration.tracing[:sequel]
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
end
