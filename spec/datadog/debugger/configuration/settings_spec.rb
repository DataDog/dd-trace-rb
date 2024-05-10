require 'spec_helper'

RSpec.describe Datadog::Debugger::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'debugger' do
    describe '#enabled' do
      subject(:enabled) { settings.debugger.enabled }

      context 'when DD_DYNAMIC_INSTRUMENTATION_ENABLED' do
        around do |example|
          ClimateControl.modify('DD_DYNAMIC_INSTRUMENTATION_ENABLED' => debugger_enabled) do
            example.run
          end
        end

        context 'is not defined' do
          let(:debugger_enabled) { nil }

          it { is_expected.to eq false }
        end

        context 'is defined' do
          let(:debugger_enabled) { 'true' }

          it { is_expected.to eq(true) }
        end
      end
    end

    describe '#enabled=' do
      subject(:set_debugger_enabled) { settings.debugger.enabled = debugger_enabled }

      [true, false].each do |value|
        context "when given #{value}" do
          let(:debugger_enabled) { value }

          before { set_debugger_enabled }

          it { expect(settings.debugger.enabled).to eq(value) }
        end
      end
    end
  end
end
