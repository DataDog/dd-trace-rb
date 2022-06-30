# typed: false

require 'spec_helper'

require 'datadog/core/telemetry/http/http_transport'
require 'datadog/core/telemetry/http/adapters/net'
require 'datadog/core/telemetry/v1/telemetry_request'

RSpec.describe Datadog::Core::Telemetry::Http::Transport do
  subject(:transport) { described_class.new }

  let(:hostname) { 'foo' }
  let(:port) { 1234 }

  describe '#initialize' do
    before do
      Datadog.configuration.agent.host = hostname
      Datadog.configuration.agent.port = port
    end
    it { expect(transport.host).to eq(hostname) }
    it { expect(transport.port).to eq(port) }
    it { expect(transport.ssl).to eq(false) }
    it { expect(transport.path).to eq(Datadog::Core::Telemetry::Http::Ext::AGENT_ENDPOINT) }
  end

  describe '#request' do
    subject(:request) { transport.request(request_type: request_type, payload: payload) }

    let(:adapter) { instance_double(Datadog::Core::Telemetry::Http::Adapters::Net, post: response) }
    let(:env) { instance_double(Datadog::Core::Telemetry::Http::Env, body: payload, path: path) }
    let(:headers) do
      {
        Datadog::Core::Telemetry::Http::Ext::HEADER_CONTENT_TYPE => 'application/json',
        Datadog::Core::Telemetry::Http::Ext::HEADER_DD_TELEMETRY_API_VERSION => 'v1',
        Datadog::Core::Telemetry::Http::Ext::HEADER_DD_TELEMETRY_REQUEST_TYPE => request_type,
      }
    end
    let(:hostname) { 'foo' }
    let(:http_connection) { instance_double(::Net::HTTP) }
    let(:path) { Datadog::Core::Telemetry::Http::Ext::AGENT_ENDPOINT }
    let(:payload) { instance_double(Datadog::Core::Telemetry::V1::TelemetryRequest) }
    let(:port) { 1234 }
    let(:request_type) { 'app-started' }
    let(:response) { instance_double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }
    let(:ssl) { false }

    before do
      Datadog.configuration.agent.host = hostname
      Datadog.configuration.agent.port = port

      allow(Datadog::Core::Telemetry::Http::Env).to receive(:new).and_return(env)
      allow(env).to receive(:path=).with(path)
      allow(env).to receive(:body=).with(payload)
      allow(env).to receive(:headers=).with(headers)

      allow(Datadog::Core::Telemetry::Http::Adapters::Net).to receive(:new)
        .with(
          hostname: hostname,
          port: port,
          ssl: ssl
        ).and_return(adapter)
    end

    it { is_expected.to be(response) }
  end
end
