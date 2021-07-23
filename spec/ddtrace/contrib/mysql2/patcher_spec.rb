require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

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
      c.use :mysql2, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:mysql2].reset_configuration!
    example.run
    Datadog.registry[:mysql2].reset_configuration!
  end

  context 'pin' do
    subject(:pin) { client.datadog_pin }

    it 'has the correct attributes' do
      expect(pin.service).to eq(service_name)
      expect(pin.app).to eq('mysql2')
      expect(pin.app_type).to eq('db')
    end
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

      context 'when a successful query is made' do
        before { client.query('SELECT 1') }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.get_tag('mysql2.db.name')).to eq(database)
          expect(span.get_tag('out.host')).to eq(host)
          expect(span.get_tag('out.port')).to eq(port)
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Contrib::Mysql2::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Contrib::Mysql2::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span'

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { client.query('SELECT INVALID') }.to raise_error(Mysql2::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('error.msg'))
            .to eq("Unknown column 'INVALID' in 'field list'")
        end
      end
    end
  end
end
