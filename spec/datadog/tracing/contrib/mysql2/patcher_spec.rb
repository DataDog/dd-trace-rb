# typed: ignore

require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

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
  let(:sql_comment_propagation) { 'disabled' }

  before do
    Datadog.configure do |c|
      c.service = 'my-service'
      c.version = '2.0.0'
      c.env = 'production'
      c.tracing.sql_comment_propagation = sql_comment_propagation
      c.tracing.instrument :mysql2, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.configuration.reset!
    example.run
    Datadog.configuration.reset!
  end

  describe 'tracing' do
    describe '#query' do
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          client.query('SELECT 1')
          expect(spans).to be_empty
        end
      end

      context 'when the client is configured directly' do
        let(:service_override) { 'mysql-override' }

        before do
          Datadog.configure_onto(client, service_name: service_override)
          client.query('SELECT 1')
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        before { client.query('SELECT 1') }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.get_tag('mysql2.db.name')).to eq(database)
          expect(span.get_tag('out.host')).to eq(host)
          expect(span.get_tag('out.port')).to eq(port)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('mysql2')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('query')
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Mysql2::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Mysql2::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { client.query('SELECT INVALID') }.to raise_error(Mysql2::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag('error.msg'))
            .to eq("Unknown column 'INVALID' in 'field list'")
        end
      end

      context 'when sql comment propagation' do
        context 'disabled' do
          it do
            client.query('SELECT 1')
          end
        end

        context 'service' do
          let(:sql_comment_propagation) { 'service' }

          it do
            client.query('SELECT 1')
          end
        end

        context 'full' do
          let(:sql_comment_propagation) { 'full' }

          it do
            client.query('SELECT 1')
          end
        end
      end
    end
  end
end
