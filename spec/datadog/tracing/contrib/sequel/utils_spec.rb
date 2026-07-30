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
      let(:uri) { "jdbc:as400://as400-host;libraries=MYLIB,OTHER" }

      it "uses the first library as the database" do
        expect(parsed).to eq(host: "as400-host", port: nil, database: "MYLIB")
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

    context "nil input" do
      let(:uri) { nil }

      it "returns all-nil without raising" do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context "authority containing user-info" do
      let(:uri) { "jdbc:mysql://user:password@db-host:3306/orders" }

      it "extracts metadata without exposing credentials" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "URI containing a fragment" do
      let(:uri) { "jdbc:mysql://db-host:3306/orders#section" }

      it "ignores the fragment" do
        expect(parsed).to eq(host: "db-host", port: "3306", database: "orders")
      end
    end

    context "multi-host authority" do
      let(:uri) { "jdbc:postgresql://host1:5432,host2:5432/analytics" }

      it "returns all-nil rather than selecting incorrect metadata" do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
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
          database: "stale-database"
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

      it "memoizes only parsed, credential-free metadata (never the raw URL)" do
        described_class.connection_metadata(db)

        cached = db.instance_variable_get(:@datadog_jdbc_metadata)
        expect(cached).to eq(host: "prod-host", port: "3111", database: "yds")
        expect(cached.to_s).not_to include("password")
        expect(cached.to_s).not_to include("jdbc:")
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
