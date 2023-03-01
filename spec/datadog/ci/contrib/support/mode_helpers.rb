require 'datadog/core/configuration/settings'
require 'datadog/core/configuration/components'

RSpec.shared_context 'CI mode activated' do
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.ci.enabled = true
    end
  end

  let(:components) { Datadog::Core::Configuration::Components.new(settings) }

  before do
    allow(Datadog::Tracing)
      .to receive(:tracer)
      .and_return(components.tracer)
  end

  after { components.shutdown! }
end
