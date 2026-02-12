require 'spec_helper'

require 'datadog/data_streams/transport/http'

RSpec.describe Datadog::DataStreams::Transport::HTTP do
  let(:logger) { logger_allowing_debug }

  describe '.default' do
    subject(:default) { described_class.default(agent_settings: agent_settings, logger: logger) }

    let(:adapter) { :net_http }
    let(:ssl) { nil }
    let(:hostname) { 'localhost' }
    let(:port) { 8126 }
    let(:uds_path) { nil }
    let(:timeout_seconds) { nil }

    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettings.new(
        adapter: adapter,
        ssl: ssl,
        hostname: hostname,
        port: port,
        uds_path: uds_path,
        timeout_seconds: timeout_seconds
      )
    end

    it 'returns a DSM stats transport' do
      is_expected.to be_a_kind_of(Datadog::DataStreams::Transport::Stats::Transport)
      expect(default.current_api_id).to eq('v0.1')

      expect(default.apis.keys).to eq(
        [
          'v0.1',
        ]
      )
    end

    it 'configures the transport with correct API endpoint' do
      api = default.apis['v0.1']
      expect(api).to be_a_kind_of(Datadog::Core::Transport::HTTP::API::Instance)
      expect(api.endpoint.path).to eq('/v0.1/pipeline_stats')
    end

    it 'configures the transport with correct headers' do
      api = default.apis['v0.1']
      expect(api.headers).to include(Datadog::Core::Transport::HTTP.default_headers)
    end

    context 'integration test with real HTTP request' do
      subject(:send_stats) { transport.send_stats(payload) }

      let(:transport) { default }
      let(:payload) { {'key' => 'value'} }

      before do
        # Stub the HTTP request to capture the request details
        stub_request(:post, 'http://localhost:8126/v0.1/pipeline_stats')
          .to_return(status: 200, body: '')
      end

      it 'sends request with correct headers from Parcel metadata' do
        send_stats

        # Verify the request was made with correct headers
        expect(WebMock).to have_requested(:post, 'http://localhost:8126/v0.1/pipeline_stats')
          .with(headers: {
            'Content-Type' => 'application/msgpack',
            'Content-Encoding' => 'gzip',
          })
      end
    end

    context 'with Net::HTTP adapter' do
      let(:adapter) { :net_http }
      let(:hostname) { 'custom-host' }
      let(:port) { 8888 }
      let(:ssl) { true }

      it 'configures the adapter correctly' do
        api = default.apis['v0.1']
        expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::Net)
        expect(api.adapter.hostname).to eq(hostname)
        expect(api.adapter.port).to eq(port)
        expect(api.adapter.ssl).to eq(ssl)
      end
    end

    context 'with Unix socket adapter' do
      let(:adapter) { :unix }
      let(:uds_path) { '/var/run/datadog/apm.socket' }

      it 'configures the adapter correctly' do
        api = default.apis['v0.1']
        expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::UnixSocket)
        expect(api.adapter.filepath).to eq(uds_path)
      end
    end
  end
end
