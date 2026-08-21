# frozen_string_literal: true

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
          MAX_JDBC_URI_BYTES = 8_192

          # Parses JDBC URLs whose subname uses `[transport:]//host...`.
          JDBC_URI_PATTERN =
            %r{\Ajdbc:[a-z][a-z0-9+.-]*:(?:[a-z][a-z0-9+.-]*:)?//(?<subname>.+)\z}im

          # Extracts the host and port from a string.
          # The host can be a multi-host value, a bracketed IPv6 host, or an ordinary host.
          HOST_AND_PORT_PATTERN =
            /\A(?:\[(?<ipv6_host>[^\[\]]+)\]|(?<host>[^,]+(?:,[^,]+)+|[^:]+))(?::(?<port>\d+))?\z/

          DATABASE_PROPERTY_PATTERN =
            /(?:\A|[&;])(?:databaseName|database)=(?<value>[^&;]+)/i
          LIBRARIES_PROPERTY_PATTERN =
            /(?:\A|[&;])libraries=,*(?<value>[^,&;]+)/i
          RFC_3986_URI_DELIMITER_PATTERN = %r{[:@\[\]?&=#]}

          private_constant :MAX_JDBC_URI_BYTES, :JDBC_URI_PATTERN,
            :DATABASE_PROPERTY_PATTERN, :LIBRARIES_PROPERTY_PATTERN,
            :RFC_3986_URI_DELIMITER_PATTERN, :HOST_AND_PORT_PATTERN

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

            # JDBC URLs are not URIs (as per RFC 3986). We can't parse it with `URI.parse`.
            # https://download.oracle.com/otn-pub/jcp/jdbc-4_3-mrel3-spec/jdbc4.3-fr-spec.pdf#page=72
            # They have the form `jdbc:<subprotocol>:<subname>`,
            # where `subname` is opaque to JDBC and driver-specific.
            #
            # The returned Hash guarantees the existence of all keys,
            # but Hash values can be `nil` when not parseable from the URL.
            #
            # @param uri [String] the JDBC URL to parse
            # @return [Hash{Symbol => String, nil}]
            #   - `:host` — host value when `subname` uses URI-style authority syntax: `//host[:port]`
            #   - `:port` — port when `subname` uses URI-style authority syntax: `//host[:port]`
            #   - `:database` — best-effort database name
            def parse_jdbc_uri(uri)
              result = {host: nil, port: nil, database: nil}
              return result unless uri.valid_encoding?

              if uri.bytesize > MAX_JDBC_URI_BYTES
                # Keep one extra byte, then let `chop` safely remove multi-byte unicode characters.
                uri = uri.byteslice(0, MAX_JDBC_URI_BYTES + 1).chop
              end

              match = JDBC_URI_PATTERN.match(uri)
              return result unless match

              # We start with: `host[:port][/database][;properties][?query]`.
              subname = match[:subname]

              # Extract `query` from the end, leaving `host[:port][/database][;properties]`.
              subname, query_separator, query = subname.partition("?")
              query = nil if query_separator.empty?

              # Extract `properties` next, leaving `host[:port][/database]`.
              subname, properties_separator, properties = subname.partition(";")
              properties = nil if properties_separator.empty?

              # Separate the authority (`host[:port]`) from the optional `database` URL path.
              authority, path = subname.split("/", 2)
              return result if authority.nil? || authority.empty?

              host, port = host_and_port_from_authority(authority)
              return result unless host

              database = database_from_path(path) ||
                database_from_properties(properties) || database_from_properties(query)

              {host: host, port: port, database: database}
            rescue Encoding::CompatibilityError, ArgumentError
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

            def database_from_path(path)
              return if path.nil? || path.empty?

              # Stop at the first URI delimiter (except `/`).
              database = path.split(RFC_3986_URI_DELIMITER_PATTERN, 2).first
              return if database.nil? || database.empty?

              database
            end

            def host_and_port_from_authority(authority)
              # Discard optional `userinfo@`, retaining only `host[:port]`.
              authority = authority.rpartition("@").last
              return if authority.empty?

              # Parse host and port.
              match = HOST_AND_PORT_PATTERN.match(authority)
              return unless match

              # Only one of `ipv6_host` or `host` will be populated.
              host = match[:ipv6_host] || match[:host]
              port = match[:port]

              [host, port]
            end

            def database_from_properties(properties)
              return unless properties

              database = DATABASE_PROPERTY_PATTERN.match(properties)
              return database[:value] if database

              libraries = LIBRARIES_PROPERTY_PATTERN.match(properties)
              libraries && libraries[:value]
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
