require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/sequel/utils'

RSpec.describe Datadog::Tracing::Contrib::Sequel::Utils do
  describe '.parse_jdbc_uri' do
    subject(:parsed) { described_class.parse_jdbc_uri(uri) }

    context 'mysql path-style with credentials' do
      let(:uri) { 'jdbc:mysql://db-host:3306/orders?user=u&password=p' }

      it 'extracts host, port, and database' do
        expect(parsed).to eq(host: 'db-host', port: '3306', database: 'orders')
      end
    end

    context 'mariadb without a port' do
      let(:uri) { 'jdbc:mariadb://db-host/orders' }

      it 'extracts host and database, leaves port nil' do
        expect(parsed).to eq(host: 'db-host', port: nil, database: 'orders')
      end
    end

    context 'postgresql path-style' do
      let(:uri) { 'jdbc:postgresql://pg-host:5432/analytics' }

      it 'extracts host, port, and database' do
        expect(parsed).to eq(host: 'pg-host', port: '5432', database: 'analytics')
      end
    end

    context 'sqlserver with semicolon databaseName property' do
      let(:uri) { 'jdbc:sqlserver://sql-host:1433;databaseName=sales;user=sa' }

      it 'recovers the database from the property' do
        expect(parsed).to eq(host: 'sql-host', port: '1433', database: 'sales')
      end
    end

    context 'as400/jt400 with default schema in the path and libraries property' do
      let(:uri) { 'jdbc:as400://as400-host/MYSCHEMA;libraries=L1,L2' }

      it 'prefers the path segment for the database' do
        expect(parsed).to eq(host: 'as400-host', port: nil, database: 'MYSCHEMA')
      end
    end

    context 'as400/jt400 with only a libraries property' do
      let(:uri) { 'jdbc:as400://as400-host;libraries=MYLIB,OTHER' }

      it 'recovers the first library as the database' do
        expect(parsed).to eq(host: 'as400-host', port: nil, database: 'MYLIB')
      end
    end

    context 'oracle thin (unsupported @-style)' do
      let(:uri) { 'jdbc:oracle:thin:@ora-host:1521:sid' }

      it 'returns all-nil (no //authority)' do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context 'not a jdbc string' do
      let(:uri) { 'mysql2://h/db' }

      it 'returns all-nil' do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context 'nil input' do
      let(:uri) { nil }

      it 'returns all-nil without raising' do
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end

    context 'invalid encoding' do
      let(:uri) { "jdbc:mysql://h\xFF\xFEst/db".b.force_encoding('UTF-8') }

      it 'is not valid UTF-8' do
        expect(uri.valid_encoding?).to eq(false)
      end

      it 'returns all-nil without raising' do
        expect { parsed }.not_to raise_error
        expect(parsed).to eq(host: nil, port: nil, database: nil)
      end
    end
  end

  describe '.connection_metadata' do
    subject(:metadata) { described_class.connection_metadata(db) }

    let(:db) { double('Sequel::Database', opts: opts) }

    context 'with a native adapter (host/database in opts)' do
      let(:opts) { {host: 'db-host', port: 3306, database: 'orders'} }

      it 'uses the opts values directly' do
        expect(metadata).to eq(host: 'db-host', port: 3306, database: 'orders')
      end
    end

    context 'with a JDBC connection string in opts[:uri] and no host' do
      let(:opts) { {uri: 'jdbc:mysql://jdbc-host:3306/catalog?user=u&password=secret'} }

      it 'parses host, port, and the clean database name from the URL' do
        expect(metadata).to eq(host: 'jdbc-host', port: '3306', database: 'catalog')
      end
    end

    context 'with a host set and a credential-bearing JDBC URL in opts[:database]' do
      let(:opts) { {host: 'db-host', database: 'jdbc:mysql://db-host/orders?user=u&password=secret'} }

      it 'never emits the raw JDBC URL or its credentials as the database name' do
        expect(metadata[:database]).to eq('orders')
        expect(metadata[:database]).not_to include('password')
        expect(metadata[:host]).to eq('db-host')
      end
    end
  end
end
