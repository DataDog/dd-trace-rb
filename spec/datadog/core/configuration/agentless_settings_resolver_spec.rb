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
end
