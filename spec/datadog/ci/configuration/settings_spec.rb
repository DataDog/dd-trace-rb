require 'datadog/ci/spec_helper'
require 'datadog/ci/configuration/settings'

require 'datadog/core/configuration/settings'
require 'datadog/tracing/flush'

RSpec.describe Datadog::CI::Configuration::Settings do
  context 'when used to extend Datadog::Core::Configuration::Settings' do
    subject(:settings) do
      # When 'datadog/ci' is required, it automatically extends Settings.
      if Datadog::Core::Configuration::Settings <= described_class
        Datadog::Core::Configuration::Settings.new
      else
        Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.extend(described_class)
        end
      end
    end

    describe '#ci' do
      describe '#enabled' do
        subject(:enabled) { settings.ci.enabled }

        it { is_expected.to be false }

        context "when #{Datadog::CI::Ext::Settings::ENV_MODE_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_MODE_ENABLED => enable) do
              example.run
            end
          end

          context 'is not defined' do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context 'is set to true' do
            let(:enable) { 'true' }

            it { is_expected.to be true }
          end

          context 'is set to false' do
            let(:enable) { 'false' }

            it { is_expected.to be false }
          end
        end
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.ci.enabled = true }
            .to change { settings.ci.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#trace_flush' do
        subject(:trace_flush) { settings.ci.trace_flush }

        context 'default' do
          it { is_expected.to be nil }
        end
      end

      describe '#trace_flush=' do
        let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

        it 'updates the #trace_flush setting' do
          expect { settings.ci.trace_flush = trace_flush }
            .to change { settings.ci.trace_flush }
            .from(nil)
            .to(trace_flush)
        end
      end

      describe '#writer_options' do
        subject(:writer_options) { settings.ci.writer_options }

        it { is_expected.to eq({}) }

        context 'when modified' do
          it 'does not modify the default by reference' do
            settings.ci.writer_options[:foo] = :bar
            expect(settings.ci.writer_options).to_not be_empty
            expect(settings.ci.options[:writer_options].default_value).to be_empty
          end
        end
      end

      describe '#writer_options=' do
        let(:options) { { priority_sampling: true } }

        it 'updates the #writer_options setting' do
          expect { settings.ci.writer_options = options }
            .to change { settings.ci.writer_options }
            .from({})
            .to(options)
        end
      end
    end
  end
end
