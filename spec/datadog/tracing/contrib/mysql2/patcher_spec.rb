require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/propagation/sql_comment'
require 'datadog/tracing/contrib/sql_comment_propagation_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'ddtrace'
require 'mysql2'

RSpec.describe 'Mysql2::Client patcher' do
  let(:service_name) { 'my-sql' }
  let(:configuration_options) { { service_name: service_name } }

  let(:client) do
    Mysql2::Client.new(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password
    )
  end

  let(:host) { ENV.fetch('TEST_MYSQL_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_MYSQL_PORT') { '3306' } }
  let(:database) { ENV.fetch('TEST_MYSQL_DB') { 'mysql' } }
  let(:username) { ENV.fetch('TEST_MYSQL_USER') { 'root' } }
  let(:password) { ENV.fetch('TEST_MYSQL_PASSWORD') { 'root' } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :mysql2, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:mysql2].reset_configuration!
    example.run
    Datadog.registry[:mysql2].reset_configuration!
  end

  describe 'tracing' do
    describe '#query' do
      subject(:query) { client.query(sql_statement) }

      let(:sql_statement) { 'SELECT 1' }

      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          query

          expect(spans).to be_empty
        end
      end

      context 'when the client is configured directly' do
        let(:service_name) { 'mysql-override' }

        before do
          Datadog.configure_onto(client, service_name: service_name)
        end

        it 'produces a trace with service override' do
          query

          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_name)
          expect(span.get_tag('span.kind')).to eq('client')
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
        end

        it_behaves_like 'with sql comment propagation', span_op_name: 'mysql2.query'
      end

      context 'when a successful query is made' do
        it 'produces a trace' do
          query

          expect(spans.count).to eq(1)
          expect(span.get_tag('span.kind')).to eq('client')
          expect(span.get_tag('mysql2.db.name')).to eq(database)
          expect(span.get_tag('out.host')).to eq(host)
          expect(span.get_tag('out.port')).to eq(port)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('mysql2')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('query')
        end

        it_behaves_like 'analytics for integration' do
          before { query }
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Mysql2::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Mysql2::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          before { query }
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false do
          before { query }
        end

        it_behaves_like 'with sql comment propagation', span_op_name: 'mysql2.query'

        it_behaves_like 'environment service name', 'DD_TRACE_MYSQL2_SERVICE_NAME' do
          let(:configuration_options) { {} }
        end
      end

      context 'when a failed query is made' do
        let(:sql_statement) { 'SELECT INVALID' }

        it 'traces failed queries' do
          expect { query }.to raise_error(Mysql2::Error)

          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('span.kind')).to eq('client')
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag('error.message'))
            .to eq("Unknown column 'INVALID' in 'field list'")
        end

        it_behaves_like 'with sql comment propagation', span_op_name: 'mysql2.query', error: Mysql2::Error

        it_behaves_like 'environment service name', 'DD_TRACE_MYSQL2_SERVICE_NAME', error: Mysql2::Error do
          let(:configuration_options) { {} }
        end
      end
    end
  end
end
