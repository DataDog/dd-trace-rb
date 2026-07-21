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

                # Sequel's JDBC adapter connects with the URL and ignores separate
                # :host/:port options, unlike native adapters where those options take precedence.
                if !parsed[:host].nil? || !parsed[:port].nil? || !parsed[:database].nil?
                  host = parsed[:host]
                  port = parsed[:port]
                end
                database = parsed[:database]
              end

              {host: host, port: port&.to_s, database: database}
            end

            private

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
