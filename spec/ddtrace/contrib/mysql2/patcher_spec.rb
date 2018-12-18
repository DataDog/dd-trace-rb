require 'spec_helper'

require 'ddtrace'
require 'mysql2'

RSpec.describe 'Mysql2::Client patcher' do
  let(:tracer) { get_test_tracer }

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

  let(:pin) { client.datadog_pin }
  let(:spans) { tracer.writer.spans(:keep) }
  let(:span) { spans.first }

  before(:each) do
    Datadog.configure do |c|
      c.use :mysql2, service_name: 'my-sql', tracer: tracer
    end
  end

  context 'pin' do
    it 'has the correct attributes' do
      expect(pin.service).to eq('my-sql')
      expect(pin.app).to eq('mysql2')
      expect(pin.app_type).to eq('db')
    end
  end

  describe 'tracing' do
    describe '#query' do
      describe 'disabled tracer' do
        before(:each) { tracer.enabled = false }

        it 'does not write spans' do
          client.query('SELECT 1')
          expect(spans).to be_empty
        end
      end

      it 'traces successful queries' do
        client.query('SELECT 1')
        expect(spans.count).to eq(1)
        expect(span.get_tag('mysql2.db.name')).to eq(database)
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port)
      end

      it 'traces failed queries' do
        expect { client.query('SELECT INVALID') }.to raise_error(Mysql2::Error)

        expect(spans.count).to eq(1)
        expect(span.status).to eq(1)
        expect(span.get_tag('error.msg'))
          .to eq("Unknown column 'INVALID' in 'field list'")
      end
    end
  end
end
