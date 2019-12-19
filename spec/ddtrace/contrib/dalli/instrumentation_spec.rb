require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'dalli'
require 'ddtrace'
require 'ddtrace/contrib/dalli/patcher'

RSpec.describe 'Dalli instrumentation' do
  let(:test_host) { ENV.fetch('TEST_MEMCACHED_HOST', '127.0.0.1') }
  let(:test_port) { ENV.fetch('TEST_MEMCACHED_PORT', '11211') }

  let(:client) { ::Dalli::Client.new("#{test_host}:#{test_port}") }
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  def all_spans
    tracer.writer.spans(:keep)
  end

  let(:span) { all_spans.first }

  # Enable the test tracer
  before(:each) do
    Datadog.configure do |c|
      c.use :dalli, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:dalli].reset_configuration!
    example.run
    Datadog.registry[:dalli].reset_configuration!
  end

  describe 'when a client calls #set' do
    before do
      client.set('abc', 123)
      try_wait_until { all_spans.any? }
    end

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Contrib::Dalli::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Dalli::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it 'calls instrumentation' do
      expect(all_spans.size).to eq(1)
      expect(span.service).to eq('memcached')
      expect(span.name).to eq('memcached.command')
      expect(span.span_type).to eq('memcached')
      expect(span.resource).to eq('SET')
      expect(span.get_tag('memcached.command')).to eq('set abc 123 0 0')
      expect(span.get_tag('out.host')).to eq(test_host)
      expect(span.get_tag('out.port')).to eq(test_port.to_f)
    end
  end

  describe 'when multiplexed configuration is provided' do
    let(:service_name) { 'multiplex-service' }

    before do
      Datadog.configure do |c|
        c.use :dalli, describes: "#{test_host}:#{test_port}", tracer: tracer, service_name: service_name
      end
    end

    context 'and #set is called' do
      before do
        client.set('abc', 123)
        try_wait_until { all_spans.any? }
      end

      it 'calls instrumentation' do
        expect(all_spans.size).to eq(1)
        expect(span.service).to eq(service_name)
        expect(span.name).to eq('memcached.command')
        expect(span.span_type).to eq('memcached')
        expect(span.resource).to eq('SET')
        expect(span.get_tag('memcached.command')).to eq('set abc 123 0 0')
        expect(span.get_tag('out.host')).to eq(test_host)
        expect(span.get_tag('out.port')).to eq(test_port.to_f)
      end
    end
  end
end
