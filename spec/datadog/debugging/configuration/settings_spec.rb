require 'spec_helper'

RSpec.describe Datadog::Debugging::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'debugging' do
    describe '#enabled' do
      subject(:enabled) { settings.debugging.enabled }

      context 'when DD_DYNAMIC_INSTRUMENTATION_ENABLED' do
        around do |example|
          ClimateControl.modify('DD_DYNAMIC_INSTRUMENTATION_ENABLED' => debugging_enabled) do
            example.run
          end
        end

        context 'is not defined' do
          let(:debugging_enabled) { nil }

          it { is_expected.to eq false }
        end

        context 'is defined' do
          let(:debugging_enabled) { 'true' }

          it { is_expected.to eq(true) }
        end
      end
    end

    describe '#enabled=' do
      subject(:set_debugging_enabled) { settings.debugging.enabled = debugging_enabled }

      [true, false].each do |value|
        context "when given #{value}" do
          let(:debugging_enabled) { value }

          before { set_debugging_enabled }

          it { expect(settings.debugging.enabled).to eq(value) }
        end
      end
    end
  end
end
