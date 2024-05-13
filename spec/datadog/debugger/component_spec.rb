require 'datadog/debugger/component'

RSpec.describe Datadog::Debugger::Component do
  describe '.build' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.debugger.enabled = debugger_enabled
      settings
    end

    context 'when debugger is enabled' do
      let(:debugger_enabled) { true }

      it 'returns a Datadog::Debugger::Component instance' do
        component = described_class.build(settings)
        expect(component).to be_a(described_class)
      end
    end

    context 'when debugger is disabled' do
      let(:debugger_enabled) { false }

      it 'returns nil' do
        component = described_class.build(settings)
        expect(component).to be nil
      end
    end
  end
end
