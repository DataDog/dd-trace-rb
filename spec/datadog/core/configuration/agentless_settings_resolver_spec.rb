require 'datadog/core/configuration/agentless_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Configuration::AgentlessSettingsResolver do
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.site = site
    end
  end

  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:logger) { Logger.new(STDERR) }

  subject(:resolver) { described_class.new(settings,
    host_prefix: host_prefix,
    url_override: url_override, url_override_source: url_override_source,
    logger: logger) }

  let(:resolved) { resolver.send(:call) }

  let(:site) { 'test.dog' }
  let(:host_prefix) { 'test-host-prefix' }
  let(:url_override) { nil }
  let(:url_override_source) { nil }

  # DD_AGENT_HOST is set in CI and alters the settings tested here
  with_env 'DD_AGENT_HOST' => nil

  context 'by default' do
    it 'returns expected values' do
      expect(resolver.send(:can_use_uds?)).to be false
      expect(resolver.send(:should_use_uds?)).to be false

      expect(resolver.send(:parsed_url)).to be nil

      expect(resolver.send(:configured_hostname)).to be nil
      expect(resolver.send(:hostname)).to eq 'test-host-prefix.test.dog'
      expect(resolver.send(:configured_port)).to be nil
      expect(resolver.send(:port)).to eq 443
      expect(resolver.send(:configured_ssl)).to be nil
      expect(resolver.send(:ssl?)).to be true
      expect(resolver.send(:configured_uds_path)).to be nil

      expect(resolved).to eq(
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: :net_http,
          hostname: 'test-host-prefix.test.dog',
          port: 443,
          ssl: true,
          timeout_seconds: 30,
        )
      )
    end
  end

  context 'when url_override is provided' do
    let(:url_override_source) { 'setting' }

    context 'url is https' do
      let(:url_override) { "https://foo.bar" }

      it 'returns expected values' do
        expect(resolver.send(:can_use_uds?)).to be false
        expect(resolver.send(:should_use_uds?)).to be false

        expect(resolver.send(:parsed_url)).to eq URI.parse(url_override)

        expect(resolver.send(:configured_hostname)).to eq 'foo.bar'
        expect(resolver.send(:hostname)).to eq 'foo.bar'
        expect(resolver.send(:configured_port)).to be 443
        expect(resolver.send(:port)).to eq 443
        expect(resolver.send(:configured_ssl)).to be true
        expect(resolver.send(:ssl?)).to be true
        expect(resolver.send(:configured_uds_path)).to be nil

        expect(resolved).to eq(
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
            adapter: :net_http,
            hostname: 'foo.bar',
            port: 443,
            ssl: true,
            timeout_seconds: 30,
          )
        )
      end
    end

    context 'url is http' do
      let(:url_override) { "http://foo.bar" }

      it 'returns expected values' do
        expect(resolver.send(:can_use_uds?)).to be false
        expect(resolver.send(:should_use_uds?)).to be false

        expect(resolver.send(:parsed_url)).to eq URI.parse(url_override)

        expect(resolver.send(:configured_hostname)).to eq 'foo.bar'
        expect(resolver.send(:hostname)).to eq 'foo.bar'
        expect(resolver.send(:configured_port)).to be 80
        expect(resolver.send(:port)).to eq 80
        expect(resolver.send(:configured_ssl)).to be false
        expect(resolver.send(:ssl?)).to be false
        expect(resolver.send(:configured_uds_path)).to be nil

        expect(resolved).to eq(
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
            adapter: :net_http,
            hostname: 'foo.bar',
            port: 80,
            ssl: false,
            timeout_seconds: 30,
          )
        )
      end
    end
  end

  context 'when timeout is overridden' do
    before do
      settings.agent.timeout_seconds = 42
    end

    it 'uses the overridden timeout' do
      expect(resolved).to eq(
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: :net_http,
          hostname: 'test-host-prefix.test.dog',
          port: 443,
          ssl: true,
          timeout_seconds: 42,
        )
      )
    end
  end

  context 'when DD_AGENT_HOST is used' do
    with_env 'DD_AGENT_HOST' => 'test-agent-host'

    it 'uses the specified host' do
      expect(resolver.send(:can_use_uds?)).to be false
      expect(resolver.send(:should_use_uds?)).to be false

      expect(resolver.send(:parsed_url)).to be nil

      expect(resolver.send(:configured_hostname)).to eq 'test-agent-host'
      expect(resolver.send(:hostname)).to eq 'test-agent-host'
      expect(resolver.send(:configured_port)).to be nil
      expect(resolver.send(:port)).to be nil
      expect(resolver.send(:configured_ssl)).to be nil
      expect(resolver.send(:ssl?)).to be false
      expect(resolver.send(:configured_uds_path)).to be nil

      expect(resolved).to eq(
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: :net_http,
          hostname: 'test-agent-host',
          port: nil,
          ssl: false,
          timeout_seconds: 30,
        )
      )
    end

    context 'when DD_AGENT_PORT is also used' do
      with_env 'DD_AGENT_PORT' => '443'

      it 'uses the specified port (but does not enable TLS)' do
        expect(resolver.send(:can_use_uds?)).to be false
        expect(resolver.send(:should_use_uds?)).to be false

        expect(resolver.send(:parsed_url)).to be nil

        expect(resolver.send(:configured_hostname)).to eq 'test-agent-host'
        expect(resolver.send(:hostname)).to eq 'test-agent-host'
        expect(resolver.send(:configured_port)).to be 443
        expect(resolver.send(:port)).to be 443
        expect(resolver.send(:configured_ssl)).to be nil
        expect(resolver.send(:ssl?)).to be false
        expect(resolver.send(:configured_uds_path)).to be nil

        expect(resolved).to eq(
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
            adapter: :net_http,
            hostname: 'test-agent-host',
            port: 443,
            ssl: false,
            timeout_seconds: 30,
          )
        )
      end
    end
  end
end
