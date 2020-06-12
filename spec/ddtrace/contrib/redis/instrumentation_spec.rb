require 'ddtrace/contrib/support/spec_helper'

require 'redis'
require 'hiredis'
require 'ddtrace'

RSpec.describe 'Redis instrumentation test' do
  let(:test_host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:test_port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  let(:client) { Redis.new(host: test_host, port: test_port) }
  let(:configuration_options) { {} }

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
  end

  before(:each) do
    skip unless ENV['TEST_DATADOG_INTEGRATION']
  end

  describe 'when multiplexed configuration is provided via url' do
    let(:default_service_name) { 'default-service' }
    let(:service_name) { 'multiplex-service' }
    let(:redis_url) { "redis://#{test_host}:#{test_port}/0" }
    let(:client) { Redis.new(url: redis_url) }

    before do
      Datadog.configure do |c|
        c.use :redis, service_name: default_service_name
        c.use :redis, describes: { url: redis_url }, service_name: service_name
      end
    end

    context 'and #set is called' do
      before do
        client.set('abc', 123)
        try_wait_until { fetch_spans.any? }
      end

      it 'calls instrumentation' do
        expect(spans.size).to eq(1)
        expect(span.service).to eq(service_name)
        expect(span.name).to eq('redis.command')
        expect(span.span_type).to eq('redis')
        expect(span.resource).to eq('SET abc 123')
        expect(span.get_tag('redis.raw_command')).to eq('SET abc 123')
        expect(span.get_tag('out.host')).to eq(test_host)
        expect(span.get_tag('out.port')).to eq(test_port.to_f)
      end
    end
  end

  describe 'when multiplexed configuration is provided via hash' do
    let(:default_service_name) { 'default-service' }
    let(:service_name) { 'multiplex-service' }
    let(:client) { Redis.new(host: test_host, port: test_port) }

    before do
      Datadog.configure do |c|
        c.use :redis, service_name: default_service_name
        c.use :redis, describes: { host: test_host, port: test_port }, service_name: service_name
      end
    end

    context 'and #set is called' do
      before do
        client.set('abc', 123)
        try_wait_until { fetch_spans.any? }
      end

      it 'calls instrumentation' do
        expect(spans.size).to eq(1)
        expect(span.service).to eq(service_name)
        expect(span.name).to eq('redis.command')
        expect(span.span_type).to eq('redis')
        expect(span.resource).to eq('SET abc 123')
        expect(span.get_tag('redis.raw_command')).to eq('SET abc 123')
        expect(span.get_tag('out.host')).to eq(test_host)
        expect(span.get_tag('out.port')).to eq(test_port.to_f)
      end
    end
  end
end
