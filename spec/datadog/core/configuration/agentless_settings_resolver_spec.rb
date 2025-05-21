require 'datadog/core/configuration/agentless_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Configuration::AgentlessSettingsResolver do
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.site = site
    end
  end
  let(:resolved) { resolver.send(:call) }
  let(:site) { 'test.dog' }
  let(:host_prefix) { 'test-host-prefix' }
  let(:url_override) { nil }
  let(:url_override_source) { nil }

  let(:logger) { instance_double(Datadog::Core::Logger) }

  subject(:resolver) do
    described_class.new(
      settings,
      host_prefix: host_prefix,
      url_override: url_override,
      url_override_source: url_override_source,
      logger: logger
    )
  end

  # DD_AGENT_HOST is set in CI and alters the settings tested here
  with_env 'DD_AGENT_HOST' => nil,
    'DD_AGENT_PORT' => nil,
    'DD_TRACE_AGENT_TIMEOUT_SECONDS' => nil

  shared_examples 'returns values expected by default' do
    it 'returns values expected by default' do
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
          uds_path: nil,
          timeout_seconds: 30,
        )
      )
    end
  end

  context 'by default' do
    include_examples 'returns values expected by default'
  end

  context 'when url_override is provided' do
    let(:url_override_source) { 'c.telemetry.agentless_url_override' }

    context 'url is https' do
      let(:url_override) { 'https://foo.bar' }

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
            uds_path: nil,
            timeout_seconds: 30,
          )
        )
      end

      context 'when url uses UDS' do
        let(:url_override) { 'unix:///var/run/test.sock' }

        it 'returns expected values' do
          expect(resolver.send(:can_use_uds?)).to be true
          expect(resolver.send(:should_use_uds?)).to be true

          expect(resolver.send(:parsed_url)).to eq URI.parse(url_override)

          expect(resolver.send(:configured_hostname)).to be nil
          expect(resolver.send(:hostname)).to be nil
          expect(resolver.send(:configured_port)).to be nil
          expect(resolver.send(:port)).to be nil
          expect(resolver.send(:configured_ssl)).to be false
          expect(resolver.send(:ssl?)).to be false
          expect(resolver.send(:configured_uds_path)).to eq '/var/run/test.sock'

          expect(resolved).to eq(
            Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
              adapter: :unix,
              hostname: nil,
              port: nil,
              ssl: false,
              uds_path: '/var/run/test.sock',
              timeout_seconds: 30,
            )
          )
        end
      end

      context 'when url uses an unknown protocol' do
        let(:url_override) { 'xyz://hello.world' }

        before do
          expect(logger).to receive(:warn).with("Invalid URI scheme 'xyz' for c.telemetry.agentless_url_override. Ignoring the contents of c.telemetry.agentless_url_override.") # rubocop:disable Layout/LineLength
        end

        include_examples 'returns values expected by default'
      end
    end

    context 'url is http' do
      let(:url_override) { 'http://foo.bar' }

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
            uds_path: nil,
            timeout_seconds: 30,
          )
        )
      end
    end
  end

  context 'when timeout is overridden' do
    shared_examples 'uses the overridden timeout' do
      it 'uses the overridden timeout' do
        expect(resolved).to eq(
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
            adapter: :net_http,
            hostname: 'test-host-prefix.test.dog',
            port: 443,
            ssl: true,
            uds_path: nil,
            timeout_seconds: 42,
          )
        )
      end
    end

    context 'programmatically' do
      before do
        settings.agent.timeout_seconds = 42
      end

      include_examples 'uses the overridden timeout'
    end

    context 'via environment variable' do
      with_env 'DD_TRACE_AGENT_TIMEOUT_SECONDS' => '42'

      include_examples 'uses the overridden timeout'
    end
  end

  context 'when DD_AGENT_HOST is used' do
    with_env 'DD_AGENT_HOST' => 'test-agent-host'

    include_examples 'returns values expected by default'

    context 'when DD_AGENT_PORT is also used' do
      with_env 'DD_AGENT_PORT' => '443'

      include_examples 'returns values expected by default'
    end
  end

  context 'when DD_AGENT_PORT is used' do
    with_env 'DD_AGENT_PORT' => '443'

    include_examples 'returns values expected by default'
  end
end
