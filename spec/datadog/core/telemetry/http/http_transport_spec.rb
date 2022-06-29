# typed: false

require 'spec_helper'

require 'datadog/core/telemetry/http/adapters/net'
require 'datadog/core/telemetry/v1/telemetry_request'

RSpec.describe Datadog::Core::Telemetry::Http::Transport do
  subject(:transport) { described_class.new(agent_settings: agent_settings) }
  let(:agent_settings) { {} }

  describe '#initialize' do
    context 'when agentless' do
      it { expect(transport.host).to eq(Datadog::Core::Telemetry::Http::Ext::AGENTLESS_HOST) }
      it { expect(transport.port).to eq(443) }
      it { expect(transport.ssl).to eq(true) }
      it { expect(transport.path).to eq(Datadog::Core::Telemetry::Http::Ext::AGENTLESS_ENDPOINT) }
    end

    context 'when not agentless' do
      it { expect(transport.host).to eq(hostname) }
      it { expect(transport.port).to eq(port) }
      it { expect(transport.ssl).to eq(false) }
      it { expect(transport.path).to eq(Datadog::Core::Telemetry::Http::Ext::AGENT_ENDPOINT) }
    end
  end

  describe '#request' do
    subject(:request) { transport.request(request_type: request_type, payload: payload) }

    let(:request_type) { 'app-started' }
    let(:payload) { instance_double(Datadog::Core::Telemetry::V1::TelemetryRequest) }
    let(:adapter) { instance_double(Datadog::Core::Telemetry::Http::Adapters::Net) }
    let(:response) { instance_double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }
    let(:hostname) { 'foo' }
    let(:port) { 1234 }
    let(:ssl) { true }
    let(:env) { instance_double(Datadog::Core::Telemetry::Http::Env) }
    let(:path) { nil }
    let(:headers) { nil }

    before do
      allow(Datadog::Core::Telemetry::Http::Env).to receive(:new).and_return(env)
      allow(env).to receive(:path=).with(path).and_return(env)
      allow(env).to receive(:body=).with(payload).and_return(env)
      allow(env).to receive(:headers=).with(headers).and_return(env)

      allow(Datadog::Core::Telemetry::Http::Adapters::Net).to receive(:new)
        .with(
          hostname: hostname,
          port: port,
          ssl: ssl
        ).and_return(adapter)

      allow(adapter).to receive(:post).and_yield(response)
    end

    context 'when agentless' do
      it do
        expect(env).to have_received(:path=).with(path)
        expect(env).to have_received(:body=).with(payload)
        expect(env).to have_received(:headers=).with(headers)
        expect(adapter).to have_received(:post).with(env)
      end
    end
  end

  describe '#agentless?' do
  end
end
