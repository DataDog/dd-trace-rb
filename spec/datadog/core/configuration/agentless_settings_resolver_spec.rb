require 'datadog/core/configuration/agentless_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Configuration::AgentlessSettingsResolver do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:logger) { Logger.new(STDERR) }

  subject(:resolver) { described_class.new(settings,
    #url_override: url_override, url_override_source: url_override_source,
    logger: logger) }

  let(:resolved) { resolver.send(:call) }

  let(:url_override) { nil }
  let(:url_override_source) { nil }

  context 'by default' do
    it 'returns' do
      expect(resolver.send(:should_use_uds?)).to be false

      expect(resolved).to eq(
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: :net_http,
          hostname: '127.0.0.1',
          port: 8126,
          ssl: false,
          timeout_seconds: 30,
        )
      )
    end
  end
end
