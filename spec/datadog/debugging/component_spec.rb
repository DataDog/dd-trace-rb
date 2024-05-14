require 'datadog/debugging/component'

RSpec.describe Datadog::Debugging::Component do
  describe '.build' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.debugging.enabled = debugging_enabled
      settings
    end

    context 'when debugging is enabled' do
      let(:debugging_enabled) { true }

      it 'returns a Datadog::Debugging::Component instance' do
        component = described_class.build(settings)
        expect(component).to be_a(described_class)
      end
    end

    context 'when debugging is disabled' do
      let(:debugging_enabled) { false }

      it 'returns nil' do
        component = described_class.build(settings)
        expect(component).to be nil
      end
    end
  end
end
