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
      dbname: database,
      user: username,
      password: password
    )
  end

  let(:host) { ENV.fetch('TEST_POSTGRES_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_POSTGRES_PORT') { '5432' } }
  let(:database) { ENV.fetch('TEST_POSTGRES_DB') { 'postgres' } }
  let(:username) { ENV.fetch('TEST_POSTGRES_USER') { 'root' } }
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
        before { conn.exec('SELECT 1;') }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.get_tag('pg.db.name')).to eq(database)
          expect(span.get_tag('out.host')).to eq(host)
          expect(span.get_tag('out.port')).to eq(port)
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('pg')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('query')
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
          expect(span.get_tag('error.message'))
            .to eq('ERROR:  column "invalid" does not exist\nLINE 1: SELECT INVALID;\n               ^')
        end
      end
    end
  end
end
