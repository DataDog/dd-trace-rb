require 'spec_helper'

require 'datadog/core/telemetry/http/transport'
require 'datadog/core/telemetry/http/adapters/net'

RSpec.describe Datadog::Core::Telemetry::Http::Transport do
  subject(:transport) { described_class.build_agent_transport }

  let(:hostname) { 'foo' }
  let(:port) { 1234 }

  describe '.build_agent_transport' do
    before do
      Datadog.configuration.agent.host = hostname
      Datadog.configuration.agent.port = port
    end
    it { expect(transport.host).to eq(hostname) }
    it { expect(transport.port).to eq(port) }
    it { expect(transport.ssl).to eq(false) }
    it { expect(transport.path).to eq(Datadog::Core::Telemetry::Http::Ext::AGENT_ENDPOINT) }
    it { expect(transport.api_key).to be_nil }
  end

  describe '.build_agentless_transport' do
    subject(:transport) { described_class.build_agentless_transport(api_key: api_key, dd_site: dd_site) }

    let(:api_key) { 'dd_api_key' }
    let(:dd_site) { 'datadoghq.com' }

    it { expect(transport.host).to eq('instrumentation-telemetry-intake.datadoghq.com') }
    it { expect(transport.port).to eq(443) }
    it { expect(transport.ssl).to eq(true) }
    it { expect(transport.path).to eq(Datadog::Core::Telemetry::Http::Ext::AGENTLESS_ENDPOINT) }
    it { expect(transport.api_key).to eq(api_key) }

    context 'when dd_site is staging' do
      let(:dd_site) { Datadog::Core::Environment::Ext::DD_SITE_STAGING }

      it { expect(transport.host).to eq('all-http-intake.logs.datad0g.com') }
    end

    context 'when dd_site is eu' do
      let(:dd_site) { 'datadoghq.eu' }

      it { expect(transport.host).to eq('instrumentation-telemetry-intake.datadoghq.eu') }
    end
  end

  describe '#request' do
    subject(:request) { transport.request(request_type: request_type, payload: payload) }

    let(:adapter) { instance_double(Datadog::Core::Telemetry::Http::Adapters::Net, post: response) }
    let(:env) { instance_double(Datadog::Core::Telemetry::Http::Env, body: payload, path: path) }
    let(:headers) do
      {
        'Content-Type' => 'application/json',
        'DD-Telemetry-API-Version' => 'v2',
        'DD-Telemetry-Request-Type' => 'app-started',
        'DD-Internal-Untraced-Request' => '1',
        'DD-Client-Library-Language' => 'ruby',
        'DD-Client-Library-Version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
      }
    end
    let(:hostname) { 'foo' }
    let(:http_connection) { instance_double(::Net::HTTP) }
    let(:path) { Datadog::Core::Telemetry::Http::Ext::AGENT_ENDPOINT }
    let(:payload) { '{"foo":"bar"}' }
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

    context 'expect api key in headers when provided' do
      let(:transport) { described_class.build_agentless_transport(api_key: api_key, dd_site: dd_site) }

      let(:api_key) { 'dd_api_key' }
      let(:dd_site) { 'datadoghq.com' }
      let(:hostname) { 'instrumentation-telemetry-intake.datadoghq.com' }
      let(:ssl) { true }
      let(:port) { 443 }
      let(:path) { Datadog::Core::Telemetry::Http::Ext::AGENTLESS_ENDPOINT }
      let(:headers) do
        {
          'Content-Type' => 'application/json',
          'DD-Telemetry-API-Version' => 'v2',
          'DD-Telemetry-Request-Type' => 'app-started',
          'DD-Internal-Untraced-Request' => '1',
          'DD-Client-Library-Language' => 'ruby',
          'DD-Client-Library-Version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
          'DD-API-KEY' => api_key
        }
      end

      it { is_expected.to be(response) }
    end
  end
end
