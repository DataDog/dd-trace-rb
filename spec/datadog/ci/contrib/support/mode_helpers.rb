require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

RSpec.shared_context 'CI mode activated' do
  let(:settings) do
    Datadog::Configuration::Settings.new.tap do |settings|
      settings.ci_mode.enabled = true
    end
  end

  let(:components) { Datadog::Configuration::Components.new(settings) }

  before do
    allow(Datadog)
      .to receive(:tracer)
      .and_return(components.tracer)
  end

  after { components.shutdown! }
end
