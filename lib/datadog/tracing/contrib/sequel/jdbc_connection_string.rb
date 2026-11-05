# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Sequel
        # Extracts connection metadata from JDBC connection strings.
        module JDBCConnectionString
          MAX_BYTES = 8_192

          # Matches JDBC connection strings whose subname uses `[transport:]//host...`.
          CONNECTION_STRING_PATTERN =
            %r{\Ajdbc:[a-z][a-z0-9+.-]*:(?:[a-z][a-z0-9+.-]*:)?//(?<subname>.+)\z}im

          # Extracts the host and port from a string.
          # The host can be a multi-host value, a bracketed IPv6 host, or an ordinary host.
          HOST_AND_PORT_PATTERN =
            /\A(?:\[(?<ipv6_host>[^\[\]]+)\]|(?<host>[^,]+(?:,[^,]+)+|[^:]+))(?::(?<port>\d+))?\z/

          DATABASE_PROPERTY_PATTERN =
            /(?:\A|[&;])(?:databaseName|database)=(?<value>[^&;]+)/i
          LIBRARIES_PROPERTY_PATTERN =
            /(?:\A|[&;])libraries=,*(?<value>[^,&;]+)/i
          DATABASE_PATH_DELIMITER_PATTERN = %r{[:@\[\]?&=#]}

          private_constant :MAX_BYTES, :CONNECTION_STRING_PATTERN,
            :DATABASE_PROPERTY_PATTERN, :LIBRARIES_PROPERTY_PATTERN,
            :DATABASE_PATH_DELIMITER_PATTERN, :HOST_AND_PORT_PATTERN

          class << self
            # The returned Hash guarantees the existence of all keys,
            # but Hash values can be `nil` when not parseable from the connection string.
            #
            # @param connection_string [String, nil] the JDBC connection string to parse
            # @return [Hash{Symbol => String, nil}]
            #   - `:host` — host value when the subname uses authority syntax: `//host[:port]`
            #   - `:port` — port when the subname uses authority syntax: `//host[:port]`
            #   - `:database` — best-effort database name
            def parse(connection_string)
              # @type var result: metadata
              result = {host: nil, port: nil, database: nil}
              return result unless connection_string.is_a?(String) && connection_string.valid_encoding?

              if connection_string.bytesize > MAX_BYTES
                # Strip userinfo before truncation. Otherwise, an `@` beyond the limit could be
                # discarded and leave a credential prefix looking like a valid authority/host.
                authority_marker = connection_string.index("//")
                if authority_marker
                  authority_start = authority_marker + 2
                  authority_end = [
                    connection_string.index("/", authority_start),
                    connection_string.index(";", authority_start),
                    connection_string.index("?", authority_start),
                  ].compact.min || connection_string.length
                  userinfo_end = connection_string.rindex("@", authority_end - 1)

                  if userinfo_end && userinfo_end >= authority_start
                    connection_string =
                      # Steep: https://github.com/soutaro/steep/issues/1219
                      connection_string[0...authority_start] + # steep:ignore NoMethod
                      connection_string[(userinfo_end + 1)..-1].to_s
                  end
                end

                # Keep one extra byte, then let `chop` safely remove multi-byte unicode characters.
                if connection_string.bytesize > MAX_BYTES
                  connection_string = connection_string.byteslice(0, MAX_BYTES + 1).chop
                end
              end

              match = CONNECTION_STRING_PATTERN.match(connection_string)
              return result unless match

              # We start with: `host[:port][/database][;properties][?query]`.
              subname = match[:subname]

              # Extract `query` from the end, leaving `host[:port][/database][;properties]`.
              subname, query_separator, query = subname.partition("?")
              query = nil if query_separator.empty?

              # Extract `properties` next, leaving `host[:port][/database]`.
              subname, properties_separator, properties = subname.partition(";")
              properties = nil if properties_separator.empty?

              # Separate the authority (`host[:port]`) from the optional database path.
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

            private

            def database_from_path(path)
              return if path.nil? || path.empty?

              database = path.split(DATABASE_PATH_DELIMITER_PATTERN, 2).first
              return if database.nil? || database.empty?

              database
            end

            def host_and_port_from_authority(authority)
              # Discard optional `userinfo@`, retaining only `host[:port]`.
              authority = authority.rpartition("@").last
              return if authority.empty?

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
          end
        end
      end
    end
  end
end
