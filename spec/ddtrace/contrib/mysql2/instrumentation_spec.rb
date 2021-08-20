require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/mysql2/instrumentation'

RSpec.describe Datadog::Contrib::Mysql2::Instrumentation::Client do
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

  describe '::get_datadog_pin' do
    subject(:pin) { described_class.get_datadog_pin(client) }

    context 'given nil' do
      let(:client) { nil }
      it { is_expected.to be nil }
    end

    context 'given a Mysql2::Client' do
      it 'has the correct attributes' do
        expect(pin.service).to eq(service_name)
        expect(pin.app).to eq('mysql2')
        expect(pin.app_type).to eq('db')
      end
    end
  end
end
