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
    it 'returns' do
      expect(resolver.send(:should_use_uds?)).to be false

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
