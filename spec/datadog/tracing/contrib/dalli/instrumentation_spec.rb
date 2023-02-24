require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'dalli'
require 'ddtrace'
require 'datadog/tracing/contrib/dalli/patcher'

RSpec.describe 'Dalli instrumentation' do
  let(:test_host) { ENV.fetch('TEST_MEMCACHED_HOST', '127.0.0.1') }
  let(:test_port) { ENV.fetch('TEST_MEMCACHED_PORT', '11211') }

  let(:client) { ::Dalli::Client.new("#{test_host}:#{test_port}") }
  let(:configuration_options) { {} }

  # Enable the test tracer
  before do
    Datadog.configure do |c|
      c.tracing.instrument :dalli, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:dalli].reset_configuration!
    example.run
    Datadog.registry[:dalli].reset_configuration!
  end

  it_behaves_like 'environment service name', 'DD_TRACE_DALLI_SERVICE_NAME' do
    subject do
      client.set('abc', 123)
      try_wait_until { fetch_spans.any? }
    end
  end

  describe 'when a client calls #set' do
    before do
      client.set('abc', 123)
      try_wait_until { fetch_spans.any? }
    end

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Dalli::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Dalli::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', false

    it 'calls instrumentation' do
      expect(spans.size).to eq(1)
      expect(span.service).to eq('memcached')
      expect(span.name).to eq('memcached.command')
      expect(span.span_type).to eq('memcached')
      expect(span.resource).to eq('SET')
      expect(span.get_tag('memcached.command')).to eq('set abc 123 0 0')
      expect(span.get_tag('out.host')).to eq(test_host)
      expect(span.get_tag('out.port')).to eq(test_port.to_f)
      expect(span.get_tag('db.system')).to eq('memcached')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND)).to eq('client')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('dalli')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('command')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_hostname) { test_host }
    end
  end

  describe 'when multiplexed configuration is provided' do
    let(:service_name) { 'multiplex-service' }

    before do
      Datadog.configure do |c|
        c.tracing.instrument :dalli, describes: "#{test_host}:#{test_port}", service_name: service_name
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
        expect(span.name).to eq('memcached.command')
        expect(span.span_type).to eq('memcached')
        expect(span.resource).to eq('SET')
        expect(span.get_tag('memcached.command')).to eq('set abc 123 0 0')
        expect(span.get_tag('out.host')).to eq(test_host)
        expect(span.get_tag('out.port')).to eq(test_port.to_f)

        expect(span.get_tag('db.system')).to eq('memcached')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND)).to eq('client')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('dalli')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('command')
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { test_host }
      end
    end
  end
end
