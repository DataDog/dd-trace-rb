# frozen_string_literal: true

require "uri"

require_relative "../../metadata/ext"
require_relative "../utils/database"
require_relative "ext"
require_relative "../ext"
require_relative "../span_attribute_schema"

module Datadog
  module Tracing
    module Contrib
      module Sequel
        # General purpose functions for Sequel
        module Utils
          JDBC_URI_PATTERN = %r{\Ajdbc:(?<vendor>[a-z][a-z0-9+.-]*):(?<location>//[^\r\n]*)\z}i
          DATABASE_PROPERTY_PATTERN =
            /(?:\A|[&;])(?<key>databaseName|database|libraries)=(?<value>[^&;]+)/i
          private_constant :JDBC_URI_PATTERN, :DATABASE_PROPERTY_PATTERN

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

            # Parses URI-style JDBC connection strings, extracting host, port, and
            # (best-effort) database name. Unsupported or ambiguous forms return empty
            # metadata rather than potentially incorrect tags.
            def parse_jdbc_uri(uri)
              result = {host: nil, port: nil, database: nil}
              return result unless uri.is_a?(String) && uri.valid_encoding?

              match = JDBC_URI_PATTERN.match(uri)
              return result unless match

              vendor = match[:vendor].downcase
              location, properties = match[:location].split(";", 2)

              # Several JDBC vendors append properties with semicolons, outside the URI
              # grammar. Parse the URI-compatible location separately from those properties.
              parsed = URI.parse("#{vendor}:#{location}")

              host = parsed.hostname
              port = parsed.port

              database = database_from_path(parsed.path) ||
                database_from_properties(properties) || database_from_properties(parsed.query)

              {host: host, port: port&.to_s, database: database}
            rescue URI::InvalidURIError, Encoding::CompatibilityError, ArgumentError
              result
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
                host: db_opts[:host]
              }
            end

            def set_common_tags(span, db)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)
              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
              span.set_tag(Contrib::Ext::DB::TAG_SYSTEM, database_type(db))

              set_metadata_tags(span, connection_metadata(db))

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
            end

            def set_connection_tags(span, conn)
              set_peer_service = !span.respond_to?(:get_tag) || span.get_tag("peer.service").nil?
              set_metadata_tags(span, connection_metadata_from_connection(conn), set_peer_service)
            end

            # Resolves the connection host/port/database for a Sequel::Database. When the
            # connection string is a JDBC URL (Sequel's JDBC adapter, used on JRuby), the
            # host/port/database are parsed from it regardless of whether opts[:host] is set.
            def connection_metadata(db)
              opts = db.opts || {}
              host = opts[:host]
              port = opts[:port]
              database = opts[:database]

              # A JDBC URL (in :uri, :url, or :database) can carry credentials, so always parse
              # it and emit only the parsed database name -- never the raw connection string.
              conn = opts[:uri] || opts[:url] || opts[:database]
              is_jdbc = conn.is_a?(String) && conn.byteslice(0, 5)&.casecmp("jdbc:") == 0
              if is_jdbc
                parsed = parse_jdbc_uri(conn)

                # JNDI/DataSource-managed connections keep only a lookup name in opts (e.g.
                # "jdbc:jndi:..."), so nothing can be parsed from it. Recover the endpoint from the
                # live connection's JDBC metadata, the same way Sequel resolves JNDI. This stays a
                # fallback rather than the primary source: it requires a connection checkout and
                # some drivers report no URL, whereas the opts URL is free and already present for
                # direct connections (and non-JDBC adapters have no such metadata at all).
                if parsed[:host].nil? && parsed[:port].nil? && parsed[:database].nil?
                  parsed = jdbc_metadata_from_connection(db) || parsed
                end

                # Sequel's JDBC adapter connects with the URL and ignores separate
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
            # Only *parsed, credential-free* metadata is memoized -- the raw URL (which can carry a
            # user/password) is used transiently and never stored or logged. A completed lookup that
            # yields no usable URL is a permanent property of the connection, so it is cached to avoid
            # re-checking out a connection on every query. A raised error is treated as transient
            # (pool checkout timeout, dropped connection, ...) and left uncached, so a later query
            # can retry once connectivity recovers.
            def jdbc_metadata_from_connection(db)
              return db.instance_variable_get(:@datadog_jdbc_metadata) if db.instance_variable_defined?(:@datadog_jdbc_metadata)

              url =
                begin
                  db.synchronize do |conn|
                    conn.get_meta_data.get_url if conn.respond_to?(:get_meta_data)
                  end
                rescue => e
                  Datadog.logger.debug { "Sequel: unable to resolve JDBC connection metadata (#{e.class})" }
                  return nil
                end

              metadata = url && parse_jdbc_uri(url)
              db.instance_variable_set(:@datadog_jdbc_metadata, metadata)
              metadata
            end

            def connection_metadata_from_connection(conn)
              metadata = jtopen_as400_connection_metadata(conn) || pg_connection_metadata(conn)

              metadata || {host: nil, port: nil, database: nil}
            end

            # Resolves connection metadata from IBM JTOpen / jt400 AS400 JDBC connections.
            # JTOpen 9.4.0 exposes AS400JDBCConnection#system and #catalog through JRuby; it does
            # not expose a public host/port API on AS400JDBCConnection. Use the system name
            # as the host and leave port unset unless a supported API is added later.
            def jtopen_as400_connection_metadata(conn)
              return unless jtopen_as400_connection?(conn)

              host = jtopen_as400_system_name(conn)
              database = conn.catalog if conn.respond_to?(:catalog)

              return unless (host && !host.empty?) || (database && !database.empty?)

              {host: host, port: nil, database: database}
            rescue => e
              Datadog.logger.debug { "Sequel: unable to resolve JTOpen AS400 connection metadata (#{e.class})" }
              nil
            end

            def jtopen_as400_connection?(conn)
              return false unless defined?(JRUBY_VERSION) && conn.respond_to?(:java_class)

              conn.java_class.name.start_with?("com.ibm.as400.access.AS400JDBCConnection")
            rescue
              false
            end

            def jtopen_as400_system_name(conn)
              system = conn.system if conn.respond_to?(:system)
              system.system_name if system && system.respond_to?(:system_name)
            end

            # Resolves the selected endpoint from the pg driver's PG::Connection API.
            # Sequel's postgres adapter subclasses PG::Connection, so conn.host/conn.port
            # are driver methods for the active libpq connection, not generic Sequel APIs.
            def pg_connection_metadata(conn)
              return unless defined?(::PG::Connection) && conn.is_a?(::PG::Connection)

              host = conn.host
              return unless host && !host.empty?

              port = conn.port
              database = conn.db

              {host: host, port: port&.to_s, database: database}
            rescue => e
              Datadog.logger.debug { "Sequel: unable to resolve PG connection metadata (#{e.class})" }
              nil
            end

            def set_metadata_tags(span, metadata, set_peer_service = true)
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

              if peer_metadata && set_peer_service
                Contrib::SpanAttributeSchema.set_peer_service!(span, Ext::PEER_SERVICE_SOURCES)
              end
            end

            def database_from_path(path)
              return unless path&.start_with?("/")

              database = path[1..-1]
              return if database.empty? || database.include?("/")

              database
            end

            def database_from_properties(properties)
              return unless properties

              match = DATABASE_PROPERTY_PATTERN.match(properties)
              return unless match

              database = match[:value]
              database = database.split(",", 2).first if match[:key].casecmp("libraries").zero?
              database
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
