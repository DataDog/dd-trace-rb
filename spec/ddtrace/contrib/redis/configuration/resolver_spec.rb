require 'spec_helper'

require 'redis'
require 'ddtrace'

RSpec.describe 'Redis configuration resolver' do
  let(:tracer) { get_test_tracer }
  let(:client) { Redis::Client.new(connection_options) }

  subject(:service_name) { Datadog::Contrib::Redis::Configuration::Resolver.new(client.options).resolve[:service_name] }

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
  end

  before do
    Datadog.configure do |c|
      c.use :redis, tracer: tracer, service_name: 'wrong-service-name'
      c.use :redis, describes: connection_options[:url] || connection_options, tracer: tracer, service_name: 'good-service-name'
    end
  end

  context 'when host, port and db provided' do
    let(:connection_options) { { host: '127.0.0.1', port: 6379, db: 0 } }

    it do
      expect(service_name).to eq('good-service-name')
    end
  end

  context 'when host and port provided' do
    let(:connection_options) { { host: '127.0.0.1', port: 6379 } }

    it do
      expect(service_name).to eq('good-service-name')
    end
  end

  context 'when host and db provided' do
    let(:connection_options) { { host: '127.0.0.1', db: 0 } }

    it do
      expect(service_name).to eq('good-service-name')
    end
  end

  context 'when unix connection string provided' do
    let(:connection_options) { { url: "unix://file/to/path" } }

    it do
      expect(service_name).to eq('good-service-name')
    end
  end

  context 'when redis connection string provided' do
    let(:connection_options) { { url: "redis://localhost:6379/0" } }

    it do
      expect(service_name).to eq('good-service-name')
    end
  end
end
