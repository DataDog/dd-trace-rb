require 'datadog/core/configuration/agent_settings'

RSpec.describe Datadog::Core::Configuration::AgentSettings do

  describe '#url' do
    context 'when using an unknown adapter' do
      it 'raises an exception' do
        agent_settings = Datadog::Core::Configuration::AgentSettings.new(adapter: :unknown)

        expect { agent_settings.url }.to raise_error(ArgumentError, /Unexpected adapter/)
      end
    end
  end
end

