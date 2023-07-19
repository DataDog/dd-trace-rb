require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'net/http'

RSpec.describe 'net/http patcher' do
  let(:host) { 'example.com' }
  let(:request_span) do
    spans.find { |span| span.name == Datadog::Tracing::Contrib::HTTP::Ext::SPAN_REQUEST }
  end

  before do
    call_web_mock_function_with_agent_host_exclusions do |options|
      WebMock.disable_net_connect!(allow_localhost: true, **options)
    end
    call_web_mock_function_with_agent_host_exclusions { |options| WebMock.enable! options }

    stub_request(:any, host)

    Datadog.configuration.tracing[:http].reset!
    Datadog.configure do |c|
      c.tracing.instrument :http
    end
  end

  describe 'with default configuration' do
    subject { Net::HTTP.get(host, '/') }

    it 'uses default service name' do
      subject
      expect(request_span.service).to eq('net/http')
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end
  end

  describe 'with changed service name' do
    let(:new_service_name) { 'new_service_name' }

    before do
      Datadog.configure do |c|
        c.tracing.instrument :http, service_name: new_service_name
      end
    end

    after do
      Datadog.configure do |c|
        c.tracing.instrument :http, service_name: Datadog::Tracing::Contrib::HTTP::Ext::DEFAULT_PEER_SERVICE_NAME
      end
    end

    subject { Net::HTTP.get(host, '/') }

    it 'uses new service name' do
      subject
      expect(request_span.service).to eq(new_service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'example.com' }
      let(:peer_service_source) { 'peer.hostname' }
    end
  end
end
