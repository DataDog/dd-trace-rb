# frozen_string_literal: true

require_relative '../../metadata/ext'
require_relative '../utils/database'
require_relative 'ext'
require_relative '../ext'
require_relative '../span_attribute_schema'

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

              if scheme == 'jdbc'
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

            # Parses a JDBC connection string of the form
            #   jdbc:<vendor>://<host>[:<port>][/<database>][?<params> | ;<params>]
            # extracting host, port, and (best-effort) database name.
            def parse_jdbc_uri(uri)
              result = {host: nil, port: nil, database: nil}
              return result unless uri.is_a?(String) && uri.valid_encoding?

              match = %r{\Ajdbc:[^:/]+://(?<authority>[^/;?]*)(?<path>/[^;?]*)?(?<params>[;?].*)?\z}i.match(uri)
              return result unless match

              host, port = match[:authority].split(':', 2)
              result[:host] = host unless host.nil? || host.empty?
              result[:port] = port if port && /\A\d+\z/.match?(port)

              if match[:path]
                database = match[:path].sub(%r{\A/}, '').split('/').first
                result[:database] = database unless database.nil? || database.empty?
              end

              if result[:database].nil? && match[:params]
                params = {}
                match[:params].sub(/\A[;?]/, '').split(/[;&]/).each do |pair|
                  key, value = pair.split('=', 2)
                  params[key.downcase] = value if key && value
                end
                db = params['databasename'] || params['database'] || params['libraries']
                db = db.split(',').first if db
                result[:database] = db unless db.nil? || db.empty?
              end

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

              # Embedded/hostless databases (e.g. SQLite) have no network peer; skip peer-identifying tags.
              if metadata[:host] && !metadata[:host].empty?
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME, metadata[:host])
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, metadata[:host])
                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, metadata[:host])
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, metadata[:port]) if metadata[:port]

                if metadata[:database] && !metadata[:database].empty?
                  span.set_tag(Contrib::Ext::DB::TAG_INSTANCE, metadata[:database])
                  span.set_tag(Ext::TAG_DB_NAME, metadata[:database])
                end

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
              if conn.is_a?(String) && /\Ajdbc:/i.match?(conn)
                parsed = parse_jdbc_uri(conn)
                host = parsed[:host] if host.nil? || host.empty?
                port ||= parsed[:port]
                database = parsed[:database]
              end

              {host: host, port: port, database: database}
            end

            private

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
