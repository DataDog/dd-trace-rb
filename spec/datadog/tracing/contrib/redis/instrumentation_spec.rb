require 'datadog/tracing/contrib/support/spec_helper'

require 'redis'
require 'ddtrace'

RSpec.describe 'Redis instrumentation test' do
  let(:test_host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:test_port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  # Redis instance supports 16 databases,
  # the default is 0 but can be changed to any number from 0-15,
  # to configure support more databases, check `redis.conf`
  # since 0 is the default, the SELECT db command would be skipped
  let(:test_database) { 15 }

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
  end

  before do
    skip unless ENV['TEST_DATADOG_INTEGRATION']
  end

  RSpec::Matchers.define :be_a_redis_span do
    match(notify_expectation_failures: true) do |span|
      expect(span.name).to eq('redis.command')
      expect(span.span_type).to eq('redis')

      expect(span.resource).to eq(@resource)
      expect(span.service).to eq(@service)

      expect(span).to_not have_error
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('redis')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('command')

      expect(span.get_tag('out.host')).to eq(@host)
      expect(span.get_tag('out.port')).to eq(@port.to_f)
      expect(span.get_tag('redis.raw_command')).to eq(@raw_command)
      expect(span.get_tag('db.system')).to eq('redis')
      expect(span.get_tag('db.redis.database_index')).to eq(@db.to_s)
    end

    chain :with do |opts|
      @resource = opts.fetch(:resource)
      @service = opts.fetch(:service)
      @raw_command = opts.fetch(:raw_command)
      @host = opts.fetch(:host)
      @port = opts.fetch(:port)
      @db = opts.fetch(:db)
    end
  end

  describe 'when multiplexed configuration is provided via url' do
    let(:default_service_name) { 'default-service' }
    let(:service_name) { 'multiplex-service' }
    let(:redis_url) { "redis://#{test_host}:#{test_port}/#{test_database}" }
    let(:redis_options) { { url: redis_url } }
    let(:client) { Redis.new(redis_options.freeze) }

    before do
      Datadog.configure do |c|
        c.tracing.instrument :redis, service_name: default_service_name
        c.tracing.instrument :redis, describes: { url: redis_url }, service_name: service_name
      end
    end

    context 'and #set is called' do
      before do
        client.set('abc', 123)
        try_wait_until { fetch_spans.any? }
      end

      it 'calls instrumentation' do
        expect(spans.size).to eq(2)

        select_db_span, span = spans

        # Select the designated database first
        expect(select_db_span).to be_a_redis_span.with(
          resource: "SELECT #{test_database}",
          service: 'multiplex-service',
          raw_command: "SELECT #{test_database}",
          host: test_host,
          port: test_port,
          db: test_database
        )

        expect(span).to be_a_redis_span.with(
          resource: 'SET abc 123',
          service: 'multiplex-service',
          raw_command: 'SET abc 123',
          host: test_host,
          port: test_port,
          db: test_database
        )

        expect(span.get_tag('span.kind')).to eq('client')
      end
    end
  end

  describe 'when multiplexed configuration is provided via hash' do
    let(:default_service_name) { 'default-service' }
    let(:service_name) { 'multiplex-service' }
    let(:redis_options) { { host: test_host, port: test_port, db: test_database } }
    let(:client) { Redis.new(redis_options.freeze) }

    before do
      Datadog.configure do |c|
        c.tracing.instrument :redis, service_name: default_service_name
        c.tracing.instrument :redis,
          describes: { host: test_host, port: test_port, db: test_database },
          service_name: service_name
      end
    end

    context 'and #set is called' do
      before do
        client.set('abc', 123)
        try_wait_until { fetch_spans.any? }
      end

      it 'calls instrumentation' do
        expect(spans.size).to eq(2)

        select_db_span, span = spans

        # Select the designated database first
        expect(select_db_span).to be_a_redis_span.with(
          resource: "SELECT #{test_database}",
          service: 'multiplex-service',
          raw_command: "SELECT #{test_database}",
          host: test_host,
          port: test_port,
          db: test_database
        )

        expect(span).to be_a_redis_span.with(
          resource: 'SET abc 123',
          service: 'multiplex-service',
          raw_command: 'SET abc 123',
          host: test_host,
          port: test_port,
          db: test_database
        )

        expect(span.get_tag('span.kind')).to eq('client')
      end
    end
  end
end
