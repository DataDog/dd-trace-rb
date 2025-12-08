require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange do
  subject(:event) {
    described_class.new(
      components: Datadog.send(:components)
    )
  }

  it 'contains only the configuration' do
    expect(event.payload.keys).to eq([:configuration])
  end
end
