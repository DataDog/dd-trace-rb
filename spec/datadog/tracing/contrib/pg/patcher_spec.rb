# typed: ignore

require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'ddtrace'
require 'pg'

RSpec.describe 'PG::Connection patcher' do
  let(:service_name) { 'pg' }
  let(:configuration_options) { { service_name: service_name } }

  let(:conn) do
    PG::Connection.new(
      host: host,
      port: port,
      dbname: dbname,
      user: user,
      password: password
    )
  end

  let(:host) { ENV.fetch('TEST_POSTGRES_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_POSTGRES_PORT') { '5432' } }
  let(:dbname) { ENV.fetch('TEST_POSTGRES_DB') { 'postgres' } }
  let(:user) { ENV.fetch('TEST_POSTGRES_USER') { 'root' } }
  let(:password) { ENV.fetch('TEST_POSTGRES_PASSWORD') { 'root' } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :pg, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:pg].reset_configuration!
    example.run
    Datadog.registry[:pg].reset_configuration!
  end

  after do
    conn.close
  end

  describe 'tracing' do
    describe '#exec' do
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.exec('SELECT 1;')
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.exec('SELECT 1;')
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        query = 'SELECT 1;'
        before { conn.exec(query) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC)
          expect(span.resource).to eq(query)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.exec('SELECT INVALID') }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('column "invalid" does not exist')
        end
      end
    end

    describe '#exec_params' do
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.exec_params('SELECT $1::int;', [1])
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.exec_params('SELECT $1::int;', [1])
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        query = 'SELECT $1::int;'
        before { conn.exec_params(query, [1]) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC_PARAMS)
          expect(span.resource).to eq(query)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.exec_params('SELECT $1;', ['INVALID']) }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('could not determine data type of parameter $1')
        end
      end
    end

    describe '#exec_prepared' do
      before { conn.prepare('prepared select 1', 'SELECT $1::int') }
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.exec_prepared('prepared select 1', [1])
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.exec_prepared('prepared select 1', [1])
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        statement_name = 'prepared select 1'
        before { conn.exec_prepared('prepared select 1', [1]) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC_PREPARED)
          expect(span.resource).to eq(statement_name)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.exec_prepared('invalid prepared select 1', ['INVALID']) }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
        end
      end
    end

    describe '#async_exec' do
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.async_exec('SELECT 1;')
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.async_exec('SELECT 1;')
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        query = 'SELECT 1;'
        before { conn.async_exec(query) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC)
          expect(span.resource).to eq(query)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.async_exec('SELECT INVALID') }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('column "invalid" does not exist')
        end
      end
    end

    describe '#async_exec_params' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #async_exec_params')
        end
      end
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.async_exec_params('SELECT $1::int;', [1])
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.async_exec_params('SELECT $1::int;', [1])
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        query = 'SELECT $1::int;'
        before { conn.async_exec_params(query, [1]) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC_PARAMS)
          expect(span.resource).to eq(query)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.async_exec_params('SELECT $1;', ['INVALID']) }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('could not determine data type of parameter $1')
        end
      end
    end

    describe '#async_exec_prepared' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #async_exec_prepared')
        end
        conn.prepare('prepared select 1', 'SELECT $1::int')
      end
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.async_exec_prepared('prepared select 1', [1])
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.async_exec_prepared('prepared select 1', [1])
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        statement_name = 'prepared select 1'
        before { conn.async_exec_prepared('prepared select 1', [1]) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC_PREPARED)
          expect(span.resource).to eq(statement_name)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.async_exec_prepared('invalid prepared select 1', ['INVALID']) }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
        end
      end
    end

    describe '#sync_exec' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #async_exec_params')
        end
      end
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.sync_exec('SELECT 1;')
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.sync_exec('SELECT 1;')
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        query = 'SELECT 1;'
        before { conn.sync_exec(query) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC)
          expect(span.resource).to eq(query)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.sync_exec('SELECT INVALID') }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('column "invalid" does not exist')
        end
      end
    end

    describe '#sync_exec_params' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #sync_exec_params')
        end
      end
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.sync_exec_params('SELECT $1::int;', [1])
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.sync_exec_params('SELECT $1::int;', [1])
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        query = 'SELECT $1::int;'
        before { conn.sync_exec_params(query, [1]) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC_PARAMS)
          expect(span.resource).to eq(query)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.sync_exec_params('SELECT $1;', ['INVALID']) }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('could not determine data type of parameter $1')
        end
      end
    end

    describe '#sync_exec_prepared' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #sync_exec_prepared')
        end
        conn.prepare('prepared select 1', 'SELECT $1::int')
      end
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          conn.sync_exec_prepared('prepared select 1', [1])
          expect(spans).to be_empty
        end
      end

      context 'when the tracer is configured directly' do
        let(:service_override) { 'pg-override' }

        before do
          Datadog.configure_onto(conn, service_name: service_override)
          conn.sync_exec_prepared('prepared select 1', [1])
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        statement_name = 'prepared select 1'
        before { conn.sync_exec_prepared('prepared select 1', [1]) }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC_PREPARED)
          expect(span.resource).to eq(statement_name)
          expect(span.service).to eq('pg')
          expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
            .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
          expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_INSTANCE)).to eq(dbname)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_USER)).to eq(user)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_SYSTEM))
            .to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYSTEM)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::DB::TAG_ROW_COUNT)).to eq(1)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { conn.sync_exec_prepared('invalid prepared select 1', ['INVALID']) }.to raise_error(PG::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
        end
      end
    end
  end
end
