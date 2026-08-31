require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/sequel/utils"

RSpec.describe Datadog::Tracing::Contrib::Sequel::Utils do
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

      it "parses host, port, and the clean database name from the connection string" do
        expect(metadata).to eq(host: "jdbc-host", port: "3306", database: "catalog")
      end
    end

    context "with stale host and port options alongside a JDBC connection string" do
      let(:opts) do
        {
          uri: "jdbc:mysql://jdbc-host:3306/catalog",
          host: "stale-host",
          port: 1234,
          database: "stale-database",
        }
      end

      it "uses the endpoint from the JDBC connection string" do
        expect(metadata).to eq(host: "jdbc-host", port: "3306", database: "catalog")
      end
    end

    context "with a host set and a credential-bearing JDBC connection string in opts[:database]" do
      let(:opts) { {host: "db-host", database: "jdbc:mysql://db-host/orders?user=u&password=secret"} }

      it "never emits the raw JDBC connection string or its credentials as the database name" do
        expect(metadata[:database]).to eq("orders")
        expect(metadata[:database]).not_to include("password")
        expect(metadata[:host]).to eq("db-host")
      end
    end

    context "with an invalidly encoded JDBC connection string" do
      let(:connection_string) { "jdbc:mysql://h\xFF\xFEst/db".b.force_encoding("UTF-8") }
      let(:opts) { {host: "db-host", port: 3306, database: connection_string} }

      # The opts value yields nothing, so the metadata fallback runs; no connection string is recoverable here.
      before { allow(db).to receive(:synchronize).and_return(nil) }

      it "does not raise or emit the raw connection string as the database name" do
        expect { metadata }.not_to raise_error
        expect(metadata).to eq(host: "db-host", port: "3306", database: nil)
      end
    end

    # This is specific to JRuby which we don't support anymore, so we cannot test against a real connection
    context "with a JNDI/DataSource connection that hides the endpoint from opts" do
      # Sequel stores only the JNDI lookup name; the real driver connection string lives on the connection.
      let(:opts) { {uri: "jdbc:jndi:java:comp/env/jdbc/ycs"} }
      let(:metadata_obj) do
        double("java.sql.DatabaseMetaData", get_url: "jdbc:mariadb://prod-host:3111/yds?user=u&password=secret")
      end
      let(:connection) { double("java.sql.Connection", get_meta_data: metadata_obj) }

      before { allow(db).to receive(:synchronize) { |&blk| blk.call(connection) } }

      it "recovers host/port/database from the live connection's JDBC metadata" do
        expect(metadata).to eq(host: "prod-host", port: "3111", database: "yds")
      end

      it "never emits the raw connection string or its credentials as the database name" do
        expect(metadata[:database]).to eq("yds")
        expect(metadata[:database]).not_to include("password")
      end

      it "resolves the connection only once, then memoizes on the database" do
        described_class.connection_metadata(db)
        described_class.connection_metadata(db)
        expect(db).to have_received(:synchronize).once
      end
    end

    context "when the JDBC driver reports no connection string (permanent)" do
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
