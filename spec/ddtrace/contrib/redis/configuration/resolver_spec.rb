require 'spec_helper'

require 'redis'
require 'ddtrace'

RSpec.describe 'Redis configuration resolver' do
  describe 'possible_configurations' do
    it 'works with a unix socket' do
      url = 'unix://file/to/path'
      redis = Redis::Client.new(url: url)

      resolver = Datadog::Contrib::Redis::Configuration::Resolver.new(redis.options)

      expect(resolver.possible_configurations).to match_array([url])
    end

    it 'works with a connection string' do
      url = 'redis://127.0.0.1:6379/0'
      redis = Redis::Client.new(url: url)

      resolver = Datadog::Contrib::Redis::Configuration::Resolver.new(redis.options)

      expect(resolver.possible_configurations).to match_array(
        [
          url,
          { host: '127.0.0.1', port: 6379, db: 0 },
          { host: '127.0.0.1', port: 6379 },
          { host: '127.0.0.1', db: 0 },
          { host: '127.0.0.1' }
        ]
      )
    end

    it 'works with host, port, db hash' do
      args = { host: '127.0.0.1', port: 6379, db: 0 }
      redis = Redis::Client.new(**args)

      resolver = Datadog::Contrib::Redis::Configuration::Resolver.new(redis.options)

      expect(resolver.possible_configurations).to match_array(
        [
          { host: '127.0.0.1', port: 6379, db: 0 },
          { host: '127.0.0.1', port: 6379 },
          { host: '127.0.0.1', db: 0 },
          { host: '127.0.0.1' }
        ]
      )
    end
  end

  describe 'resolve' do
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
        describes = connection_options[:url] || connection_options
        c.use :redis, describes: describes, tracer: tracer, service_name: 'good-service-name'
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
      let(:connection_options) { { url: 'unix://file/to/path' } }

      it do
        expect(service_name).to eq('good-service-name')
      end
    end

    context 'when redis connection string provided' do
      let(:connection_options) { { url: 'redis://localhost:6379/0' } }

      it do
        expect(service_name).to eq('good-service-name')
      end
    end
  end
end
