require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/sequel/jdbc_connection_string"

RSpec.describe Datadog::Tracing::Contrib::Sequel::JDBCConnectionString do
  describe ".parse" do
    subject(:parsed) { described_class.parse(connection_string) }

    context "mysql path-style with credentials" do
      let(:connection_string) { "jdbc:mysql://db-host:3306/orders?user=u&password=p" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "mariadb without a port" do
      let(:connection_string) { "jdbc:mariadb://db-host/orders" }

      it "extracts host and database, leaves port nil" do
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end
    end

    # Connector/J parses query properties without applying fragment semantics:
    # https://github.com/mariadb-corporation/mariadb-connector-j/blob/3.5.10/src/main/java/org/mariadb/jdbc/Configuration.java#L832-L844
    context "when a loose fragment delimiter (#) appears in a MariaDB connection string" do
      let(:connection_string) { "jdbc:mariadb://db-host:3306/example?pwd=containing# a_hash_and_space" }

      it "does not consider it a fragment delimiter" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "example")
      end

      context "with query arguments after the loose `#`" do
        let(:connection_string) { "jdbc:mariadb://db-host:3306?pwd=# foo&database=orders" }

        it "continues parsing query arguments" do
          expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
        end
      end
    end

    context "postgresql path-style" do
      let(:connection_string) { "jdbc:postgresql://pg-host:5432/analytics" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "pg-host", port: "5432", database: "analytics")
      end
    end

    context "postgresql with a bracketed IPv6 host" do
      let(:connection_string) { "jdbc:postgresql://[2001:db8::1]:5432/analytics" }

      it "extracts the host without brackets" do
        expect(parsed).to eq(host: "2001:db8::1", port: "5432", database: "analytics")
      end
    end

    # This driver strips brackets without validating that their contents are an IPv6 address:
    # https://github.com/mariadb-corporation/mariadb-connector-j/blob/3.5.10/src/main/java/org/mariadb/jdbc/HostAddress.java
    context "with a bracketed hostname, accepted by MariaDB Connector/J" do
      let(:connection_string) { "jdbc:mariadb://[hostname]:1234/database" }

      it "extracts clean host" do
        expect(parsed).to eq(host: "hostname", port: "1234", database: "database")
      end
    end

    context "another vendor using the same connection string form" do
      let(:connection_string) { "jdbc:db2://db-host:50000/warehouse" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "db-host", port: "50000", database: "warehouse")
      end
    end

    context "mysql with the database in the query" do
      let(:connection_string) { "jdbc:mysql://db-host:3306?database=&user=u&password=p&database=orders" }

      it "extracts the first non-empty allowlisted value" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "sqlserver with a semicolon databaseName property" do
      let(:connection_string) { "jdbc:sqlserver://sql-host:1433;user=sa;password=secret;databaseName=sales" }

      it "extracts metadata without exposing credentials" do
        expect(parsed).to eq(host: "sql-host", port: "1433", database: "sales")
      end
    end

    context "as400 with a default schema in the path and libraries property" do
      let(:connection_string) { "jdbc:as400://as400-host/MYSCHEMA;libraries=L1,L2" }

      it "prefers the path schema" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "MYSCHEMA")
      end
    end

    context "as400 with only a libraries property" do
      let(:connection_string) { "jdbc:as400://as400-host;libraries=,MYLIB,OTHER" }

      it "uses the first non-empty library as the database" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "MYLIB")
      end
    end

    # This is a contrived example, simply to document the precedence order as
    # both `libraries` and `database` are not used by the same driver implementation.
    context "with libraries before another database property" do
      let(:connection_string) { "jdbc:as400://as400-host;libraries=FIRST,OTHER;database=second" }

      it "prefers the explicit database property" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "second")
      end
    end

    context "another vendor with a semicolon database property" do
      let(:connection_string) { "jdbc:acme://db-host:1234;database=warehouse" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "db-host", port: "1234", database: "warehouse")
      end
    end

    context "oracle thin (unsupported @-style)" do
      let(:connection_string) { "jdbc:oracle:thin:@ora-host:1521:sid" }

      it "returns all-nil (no //authority)" do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "not a jdbc string" do
      let(:connection_string) { "mysql2://h/db" }

      it "returns all-nil" do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "with nil input" do
      let(:connection_string) { nil }

      it "returns all-nil without raising" do
        expect { parsed }.not_to raise_error
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "authority containing user-info" do
      let(:connection_string) { "jdbc:mysql://user:password@db-host:3306/orders" }

      it "extracts metadata without exposing credentials" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "with reserved delimiters in the connection string path" do
      [":", "@", "[", "]", "?", "&", "=", "#"].each do |delimiter|
        context "with delimiter `#{delimiter.inspect}`" do
          let(:connection_string) { "jdbc:mariadb://db-host:3306/orders#{delimiter}section" }

          it "extracts the path before the delimiter as the database" do
            expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
          end
        end
      end
    end

    context "when the database path contains multiple segments" do
      let(:connection_string) { "jdbc:mariadb://db-host:3306/orders/archive/2025" }

      it "extracts the complete path as database" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders/archive/2025")
      end
    end

    # H2 remote connection strings allow a filesystem-style path before the database name:
    # https://h2database.github.io/html/features.html#database_url
    context "with an H2 server-side database path" do
      let(:connection_string) { "jdbc:h2:tcp://db-host:9092/data/archive/orders" }

      it "extracts the complete path as database" do
        expect(parsed).to eq(host: "db-host", port: "9092", database: "data/archive/orders")
      end
    end

    context "multi-host authority" do
      let(:connection_string) { "jdbc:postgresql://host1:5432,host2:5432/analytics" }

      it "keeps the multi-host value as the host" do
        expect(parsed).to eq(host: "host1:5432,host2:5432", port: nil, database: "analytics")
      end
    end

    context "with opaque control characters in a query property" do
      let(:connection_string) { "jdbc:mariadb://db-host/orders?pwd=\r\n\0" }

      it "extracts metadata without interpreting the property" do
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end
    end

    context "with an empty or missing authority" do
      [
        "jdbc:x://",
        "jdbc:x://?a=b",
        "jdbc:x://;a=b",
        "jdbc:x:///database",
        "jdbc:x://user:password@",
      ].each do |malformed_connection_string|
        context "with #{malformed_connection_string.inspect}" do
          let(:connection_string) { malformed_connection_string }

          it "returns an empty result" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "with an empty path" do
      let(:connection_string) { "jdbc:mysql://db-host:123/" }

      it "retains authority metadata" do
        expect(parsed).to eq(host: "db-host", port: "123", database: nil)
      end
    end

    context "with malformed authorities" do
      [
        "host:12:34",
        "[2001:db8::1",
        "2001:db8::1",
        "[[2001:db8::1]]:1234",
      ].each do |authority|
        context "with #{authority.inspect}" do
          let(:connection_string) { "jdbc:x://#{authority}/database" }

          it "does not guess a host" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "with a port" do
      ["0", "1", "65535"].each do |port|
        context "with #{port.inspect}" do
          let(:connection_string) { "jdbc:x://host:#{port}/database" }

          it "accepts the sequence of digits" do
            expect(parsed).to eq(host: "host", port: port, database: "database")
          end
        end
      end

      ["", "+1", "-1", "12x"].each do |port|
        context "with invalid port #{port.inspect}" do
          let(:connection_string) { "jdbc:x://host:#{port}/database" }

          it "does not retain partial metadata" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "at the JDBC connection string size limit" do
      let(:maximum_size) { 8_192 }
      let(:prefix) { "jdbc:mysql://db-host?padding=" }
      let(:database_property) { "&database=orders" }
      let(:connection_string) do
        prefix + ("x" * (maximum_size - prefix.bytesize - database_property.bytesize)) + database_property
      end

      it "extracts a database property ending at the limit" do
        expect(connection_string.bytesize).to eq(maximum_size)
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end
    end

    context "over the JDBC connection string size limit" do
      let(:maximum_size) { 8_192 }
      let(:prefix) { "jdbc:mysql://db-host?padding=" }
      let(:database_property) { "&database=orders" }
      let(:connection_string) do
        prefix + ("x" * (maximum_size - prefix.bytesize - database_property.bytesize)) + database_property + "x"
      end

      it "extracts the database property only through the first 8 KiB" do
        expect(connection_string.bytesize).to eq(maximum_size + 1)
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end

      it "discards a partial multibyte database value at the boundary" do
        connection_string = prefix +
          ("x" * (maximum_size - prefix.bytesize - database_property.bytesize - 1)) +
          database_property + "€"

        expect(connection_string.bytesize).to eq(maximum_size + 2)
        expect(described_class.parse(connection_string))
          .to eq(host: "db-host", port: nil, database: "orders")
      end

      it "removes userinfo before truncating an authority" do
        connection_string = "jdbc:mysql://user:#{"secret," * 1_200}@db-host:3306/orders"

        expect(connection_string.index("@")).to be > maximum_size
        expect(described_class.parse(connection_string))
          .to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "with an encoding that cannot be matched using the standard ASCII regexp" do
      let(:connection_string) { "jdbc:mysql://host/database".encode("UTF-16LE") }

      it "returns an empty result" do
        expect { parsed }.not_to raise_error
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "with malformed JDBC input" do
      [
        "jdbc:",
        "jdbc:x:",
        "jdbc:://host/database",
        "jdbc:x:/host/database",
      ].each do |input|
        context "with #{input.inspect}" do
          let(:connection_string) { input }

          it "returns an empty result" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "invalid encoding" do
      let(:connection_string) { "jdbc:mysql://h\xFF\xFEst/db".b.force_encoding("UTF-8") }

      it "is not valid UTF-8" do
        expect(connection_string.valid_encoding?).to eq(false)
      end

      it "returns all-nil without raising" do
        expect { parsed }.not_to raise_error
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end
  end
end
