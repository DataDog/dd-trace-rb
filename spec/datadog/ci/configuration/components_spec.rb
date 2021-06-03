require 'datadog/ci/spec_helper'
require 'datadog/ci/configuration/components'

RSpec.describe Datadog::CI::Configuration::Components do
  context 'when used to extend Datadog::Configuration::Components' do
    subject(:components) do
      # When 'datadog/ci' is required, it automatically extends Components.
      components = if Datadog::Configuration::Components <= described_class
                     Datadog::Configuration::Components.new(settings)
                   else
                     components_class = Datadog::Configuration::Components.dup
                     components_class.prepend(described_class)
                     components_class.new(settings)
                   end

      components
    end

    let(:settings) do
      # When 'datadog/ci' is required, it automatically extends Settings.
      if Datadog::Configuration::Settings <= Datadog::CI::Configuration::Settings
        Datadog::Configuration::Settings.new
      else
        Datadog::Configuration::Settings.new.tap do |settings|
          settings.extend(Datadog::CI::Configuration::Settings)
        end
      end
    end

    after { components.shutdown! }

    describe '::new' do
      context 'when #ci_mode' do
        before do
          # Stub CI mode behavior
          allow(settings.ci_mode)
            .to receive(:enabled)
            .and_return(enabled)

          # Spy on test mode behavior
          allow(settings.test_mode)
            .to receive(:enabled=)

          allow(settings.test_mode)
            .to receive(:context_flush=)

          allow(settings.test_mode)
            .to receive(:writer_options=)

          components
        end

        context 'is enabled' do
          let(:enabled) { true }

          it do
            expect(settings.test_mode)
              .to have_received(:enabled=)
              .with(true)
          end

          it do
            expect(settings.test_mode)
              .to have_received(:context_flush=)
              .with(settings.ci_mode.context_flush || kind_of(Datadog::CI::ContextFlush::Finished))
          end

          it do
            expect(settings.test_mode)
              .to have_received(:writer_options=)
              .with(settings.ci_mode.writer_options)
          end
        end

        context 'is disabled' do
          let(:enabled) { false }

          it do
            expect(settings.test_mode)
              .to_not have_received(:enabled=)
          end

          it do
            expect(settings.test_mode)
              .to_not have_received(:context_flush=)
          end

          it do
            expect(settings.test_mode)
              .to_not have_received(:writer_options=)
          end
        end
      end
    end
  end
end
