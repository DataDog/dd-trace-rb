require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange do
  subject(:event) { described_class.new(
    agent_settings: instance_double(Datadog::Core::Configuration::AgentSettings, adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER),
    settings: Datadog.configuration) }

  it 'contains only the configuration' do
    expect(event.payload.keys).to eq([:configuration])
  end
end
