require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/sequel/utils"

RSpec.describe Datadog::Tracing::Contrib::Sequel::Utils do
  describe ".parse_jdbc_uri" do
    subject(:parsed) { described_class.parse_jdbc_uri(uri) }

    context "mysql path-style with credentials" do
      let(:uri) { "jdbc:mysql://db-host:3306/orders?user=u&password=p" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "mariadb without a port" do
      let(:uri) { "jdbc:mariadb://db-host/orders" }

      it "extracts host and database, leaves port nil" do
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end
    end

    # Connector/J parses query properties without applying URI fragment semantics:
    # https://github.com/mariadb-corporation/mariadb-connector-j/blob/3.5.10/src/main/java/org/mariadb/jdbc/Configuration.java#L832-L844
    context "when a loose fragment delimiter (#) appears in a MariaDB Connector/J URL" do
      let(:uri) { "jdbc:mariadb://db-host:3306/example?pwd=containing# a_hash_and_space" }

      it "does not consider it a fragment delimiter" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "example")
      end

      context "with query arguments after the loose `#`" do
        let(:uri) { "jdbc:mariadb://db-host:3306?pwd=# foo&database=orders" }

        it "continues parsing query arguments" do
          expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
        end
      end
    end

    context "postgresql path-style" do
      let(:uri) { "jdbc:postgresql://pg-host:5432/analytics" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "pg-host", port: "5432", database: "analytics")
      end
    end

    context "postgresql with a bracketed IPv6 host" do
      let(:uri) { "jdbc:postgresql://[2001:db8::1]:5432/analytics" }

      it "extracts the host without brackets" do
        expect(parsed).to eq(host: "2001:db8::1", port: "5432", database: "analytics")
      end
    end

    # This driver strips brackets without validating that their contents are an IPv6 address:
    # https://github.com/mariadb-corporation/mariadb-connector-j/blob/3.5.10/src/main/java/org/mariadb/jdbc/HostAddress.java
    context "with a bracketed hostname, accepted by MariaDB Connector/J" do
      let(:uri) { "jdbc:mariadb://[hostname]:1234/database" }

      it "extracts clean host" do
        expect(parsed).to eq(host: "hostname", port: "1234", database: "database")
      end
    end

    context "another vendor using the same URI form" do
      let(:uri) { "jdbc:db2://db-host:50000/warehouse" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "db-host", port: "50000", database: "warehouse")
      end
    end

    context "mysql with the database in the query" do
      let(:uri) { "jdbc:mysql://db-host:3306?database=&user=u&password=p&database=orders" }

      it "extracts the first non-empty allowlisted value" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "sqlserver with a semicolon databaseName property" do
      let(:uri) { "jdbc:sqlserver://sql-host:1433;user=sa;password=secret;databaseName=sales" }

      it "extracts metadata without exposing credentials" do
        expect(parsed).to eq(host: "sql-host", port: "1433", database: "sales")
      end
    end

    context "as400 with a default schema in the path and libraries property" do
      let(:uri) { "jdbc:as400://as400-host/MYSCHEMA;libraries=L1,L2" }

      it "prefers the path schema" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "MYSCHEMA")
      end
    end

    context "as400 with only a libraries property" do
      let(:uri) { "jdbc:as400://as400-host;libraries=,MYLIB,OTHER" }

      it "uses the first non-empty library as the database" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "MYLIB")
      end
    end

    # This is a contrived example, simply to document the precedence order as
    # both `libraries` and `database` are not used by the same driver implementation.
    context "with libraries before another database property" do
      let(:uri) { "jdbc:as400://as400-host;libraries=FIRST,OTHER;database=second" }

      it "prefers the explicit database property" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "second")
      end
    end

    context "another vendor with a semicolon database property" do
      let(:uri) { "jdbc:acme://db-host:1234;database=warehouse" }

      it "extracts host, port, and database" do
        expect(parsed).to eq(host: "db-host", port: "1234", database: "warehouse")
      end
    end

    context "oracle thin (unsupported @-style)" do
      let(:uri) { "jdbc:oracle:thin:@ora-host:1521:sid" }

      it "returns all-nil (no //authority)" do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "not a jdbc string" do
      let(:uri) { "mysql2://h/db" }

      it "returns all-nil" do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "with nil input" do
      let(:uri) { nil }

      it "returns all-nil without raising" do
        expect { parsed }.not_to raise_error
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "authority containing user-info" do
      let(:uri) { "jdbc:mysql://user:password@db-host:3306/orders" }

      it "extracts metadata without exposing credentials" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "with URI delimiters in the URL path" do
      [":", "@", "[", "]", "?", "&", "=", "#"].each do |delimiter|
        context "with delimiter `#{delimiter.inspect}`" do
          let(:uri) { "jdbc:mariadb://db-host:3306/orders#{delimiter}section" }

          it "extracts the path before the delimiter as the database" do
            expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
          end
        end
      end
    end

    context "when the database path contains multiple segments" do
      let(:uri) { "jdbc:mariadb://db-host:3306/orders/archive/2025" }

      it "extracts the complete path as database" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders/archive/2025")
      end
    end

    # H2 remote URLs allow a filesystem-style path before the database name:
    # https://h2database.github.io/html/features.html#database_url
    context "with an H2 server-side database path" do
      let(:uri) { "jdbc:h2:tcp://db-host:9092/data/archive/orders" }

      it "extracts the complete path as database" do
        expect(parsed).to eq(host: "db-host", port: "9092", database: "data/archive/orders")
      end
    end

    context "multi-host authority" do
      let(:uri) { "jdbc:postgresql://host1:5432,host2:5432/analytics" }

      it "keeps the multi-host value as the host" do
        expect(parsed).to eq(host: "host1:5432,host2:5432", port: nil, database: "analytics")
      end
    end

    context "with opaque control characters in a query property" do
      let(:uri) { "jdbc:mariadb://db-host/orders?pwd=\r\n\0" }

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
      ].each do |malformed_uri|
        context "with #{malformed_uri.inspect}" do
          let(:uri) { malformed_uri }

          it "returns an empty result" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "with an empty path" do
      let(:uri) { "jdbc:mysql://db-host:123/" }

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
          let(:uri) { "jdbc:x://#{authority}/database" }

          it "does not guess a host" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "with a port" do
      ["0", "1", "65535"].each do |port|
        context "with #{port.inspect}" do
          let(:uri) { "jdbc:x://host:#{port}/database" }

          it "accepts the sequence of digits" do
            expect(parsed).to eq(host: "host", port: port, database: "database")
          end
        end
      end

      ["", "+1", "-1", "12x"].each do |port|
        context "with invalid port #{port.inspect}" do
          let(:uri) { "jdbc:x://host:#{port}/database" }

          it "does not retain partial metadata" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "at the JDBC URL size limit" do
      let(:maximum_size) { 8_192 }
      let(:prefix) { "jdbc:mysql://db-host?padding=" }
      let(:database_property) { "&database=orders" }
      let(:uri) do
        prefix + ("x" * (maximum_size - prefix.bytesize - database_property.bytesize)) + database_property
      end

      it "extracts a database property ending at the limit" do
        expect(uri.bytesize).to eq(maximum_size)
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end
    end

    context "over the JDBC URL size limit" do
      let(:maximum_size) { 8_192 }
      let(:prefix) { "jdbc:mysql://db-host?padding=" }
      let(:database_property) { "&database=orders" }
      let(:uri) do
        prefix + ("x" * (maximum_size - prefix.bytesize - database_property.bytesize)) + database_property + "x"
      end

      it "extracts the database property only through the first 8 KiB" do
        expect(uri.bytesize).to eq(maximum_size + 1)
        expect(parsed).to eq(host: "db-host", port: nil, database: "orders")
      end

      it "discards a partial multibyte database value at the boundary" do
        uri = prefix +
          ("x" * (maximum_size - prefix.bytesize - database_property.bytesize - 1)) +
          database_property + "€"

        expect(uri.bytesize).to eq(maximum_size + 2)
        expect(described_class.parse_jdbc_uri(uri))
          .to eq(host: "db-host", port: nil, database: "orders")
      end

      it "removes userinfo before truncating an authority" do
        uri = "jdbc:mysql://user:#{"secret," * 1_200}@db-host:3306/orders"

        expect(uri.index("@")).to be > maximum_size
        expect(described_class.parse_jdbc_uri(uri))
          .to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "with an encoding that cannot be matched using the standard ASCII regexp" do
      let(:uri) { "jdbc:mysql://host/database".encode("UTF-16LE") }

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
          let(:uri) { input }

          it "returns an empty result" do
            expect(parsed).to eq(host: nil, port: nil, database: nil)
          end
        end
      end
    end

    context "invalid encoding" do
      let(:uri) { "jdbc:mysql://h\xFF\xFEst/db".b.force_encoding("UTF-8") }

      it "is not valid UTF-8" do
        expect(uri.valid_encoding?).to eq(false)
      end

      it "returns all-nil without raising" do
        expect { parsed }.not_to raise_error
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end
  end

  describe ".set_common_tags" do
    subject(:set_common_tags) { described_class.set_common_tags(span, db) }

    let(:span) { spy("span") }
    let(:db) { double("Sequel::Database", database_type: :mysql, opts: {host: "", database: "orders"}) }

    before do
      allow(Datadog::Tracing::Contrib::SpanAttributeSchema).to receive(:set_peer_service!)
    end

    it "tags the database and infers peer.service without adding an empty host" do
      set_common_tags

      expect(span).not_to have_received(:set_tag)
        .with(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, "")
      expect(span).to have_received(:set_tag)
        .with(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE, "orders")
      expect(span).to have_received(:set_tag)
        .with(Datadog::Tracing::Contrib::Sequel::Ext::TAG_DB_NAME, "orders")
      expect(Datadog::Tracing::Contrib::SpanAttributeSchema).to have_received(:set_peer_service!)
        .with(span, Datadog::Tracing::Contrib::Sequel::Ext::PEER_SERVICE_SOURCES)
    end
  end

  describe ".connection_metadata" do
    subject(:metadata) { described_class.connection_metadata(db) }

    let(:db) { double("Sequel::Database", opts: opts) }

    context "with a native adapter (host/database in opts)" do
      let(:opts) { {host: "db-host", port: 3306, database: "orders"} }

      it "uses the opts values directly" do
        expect(metadata).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "with a JDBC connection string in opts[:uri] and no host" do
      let(:opts) { {uri: "jdbc:mysql://jdbc-host:3306/catalog?user=u&password=secret"} }

      it "parses host, port, and the clean database name from the URL" do
        expect(metadata).to eq(host: "jdbc-host", port: "3306", database: "catalog")
      end
    end

    context "with stale host and port options alongside a JDBC URI" do
      let(:opts) do
        {
          uri: "jdbc:mysql://jdbc-host:3306/catalog",
          host: "stale-host",
          port: 1234,
          database: "stale-database",
        }
      end

      it "uses the endpoint from the JDBC URI" do
        expect(metadata).to eq(host: "jdbc-host", port: "3306", database: "catalog")
      end
    end

    context "with a host set and a credential-bearing JDBC URL in opts[:database]" do
      let(:opts) { {host: "db-host", database: "jdbc:mysql://db-host/orders?user=u&password=secret"} }

      it "never emits the raw JDBC URL or its credentials as the database name" do
        expect(metadata[:database]).to eq("orders")
        expect(metadata[:database]).not_to include("password")
        expect(metadata[:host]).to eq("db-host")
      end
    end

    context "with an invalidly encoded JDBC URL" do
      let(:uri) { "jdbc:mysql://h\xFF\xFEst/db".b.force_encoding("UTF-8") }
      let(:opts) { {host: "db-host", port: 3306, database: uri} }

      # The opts URL yields nothing, so the metadata fallback runs; no URL is recoverable here.
      before { allow(db).to receive(:synchronize).and_return(nil) }

      it "does not raise or emit the raw URL as the database name" do
        expect { metadata }.not_to raise_error
        expect(metadata).to eq(host: "db-host", port: "3306", database: nil)
      end
    end

    # This is specific to JRuby which we don't support anymore, so we cannot test against a real connection
    context "with a JNDI/DataSource connection that hides the endpoint from opts" do
      # Sequel stores only the JNDI lookup name; the real driver URL lives on the connection.
      let(:opts) { {uri: "jdbc:jndi:java:comp/env/jdbc/ycs"} }
      let(:metadata_obj) do
        double("java.sql.DatabaseMetaData", get_url: "jdbc:mariadb://prod-host:3111/yds?user=u&password=secret")
      end
      let(:connection) { double("java.sql.Connection", get_meta_data: metadata_obj) }

      before { allow(db).to receive(:synchronize) { |&blk| blk.call(connection) } }

      it "recovers host/port/database from the live connection's JDBC metadata" do
        expect(metadata).to eq(host: "prod-host", port: "3111", database: "yds")
      end

      it "never emits the raw URL or its credentials as the database name" do
        expect(metadata[:database]).to eq("yds")
        expect(metadata[:database]).not_to include("password")
      end

      it "resolves the connection only once, then memoizes on the database" do
        described_class.connection_metadata(db)
        described_class.connection_metadata(db)
        expect(db).to have_received(:synchronize).once
      end
    end

    context "when the JDBC driver reports no URL (permanent)" do
      let(:opts) { {uri: "jdbc:jndi:java:comp/env/jdbc/ycs"} }
      let(:metadata_obj) { double("java.sql.DatabaseMetaData", get_url: nil) }
      let(:connection) { double("java.sql.Connection", get_meta_data: metadata_obj) }

      before { allow(db).to receive(:synchronize) { |&blk| blk.call(connection) } }

      it "returns empty metadata and caches it (no re-checkout per query)" do
        expect(metadata).to eq(host: nil, port: nil, database: nil)
        described_class.connection_metadata(db)
        expect(db).to have_received(:synchronize).once
      end
    end

    context "when metadata resolution fails transiently" do
      let(:opts) { {uri: "jdbc:jndi:java:comp/env/jdbc/ycs"} }
      let(:metadata_obj) { double("java.sql.DatabaseMetaData", get_url: "jdbc:mariadb://prod-host:3111/yds") }
      let(:connection) { double("java.sql.Connection", get_meta_data: metadata_obj) }

      it "does not cache the failure and recovers on a later call" do
        calls = 0
        allow(db).to receive(:synchronize) do |&blk|
          calls += 1
          raise "pool checkout timeout" if calls == 1
          blk.call(connection)
        end

        expect(described_class.connection_metadata(db)).to eq(host: nil, port: nil, database: nil)
        expect(described_class.connection_metadata(db)).to eq(host: "prod-host", port: "3111", database: "yds")
        expect(db).to have_received(:synchronize).twice
      end
    end
  end
end
