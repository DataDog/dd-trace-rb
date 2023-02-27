require 'datadog/ci/spec_helper'

require 'datadog/ci/configuration/components'
require 'datadog/ci/configuration/settings'
require 'datadog/ci/flush'
require 'datadog/core/configuration/components'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::CI::Configuration::Components do
  context 'when used to extend Datadog::Core::Configuration::Components' do
    subject(:components) do
      # When 'datadog/ci' is required, it automatically extends Components.
      components = if Datadog::Core::Configuration::Components <= described_class
                     Datadog::Core::Configuration::Components.new(settings)
                   else
                     components_class = Datadog::Core::Configuration::Components.dup
                     components_class.prepend(described_class)
                     components_class.new(settings)
                   end

      components
    end

    let(:settings) do
      # When 'datadog/ci' is required, it automatically extends Settings.
      if Datadog::Core::Configuration::Settings <= Datadog::CI::Configuration::Settings
        Datadog::Core::Configuration::Settings.new
      else
        Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.extend(Datadog::CI::Configuration::Settings)
        end
      end
    end

    after do
      components.telemetry.worker.stop(true)
      components.telemetry.worker.join
      components.shutdown!
    end

    describe '::new' do
      context 'when #ci' do
        before do
          # Stub CI mode behavior
          allow(settings.ci)
            .to receive(:enabled)
            .and_return(enabled)

          # Spy on test mode behavior
          allow(settings.tracing.test_mode)
            .to receive(:enabled=)

          allow(settings.tracing.test_mode)
            .to receive(:trace_flush=)

          allow(settings.tracing.test_mode)
            .to receive(:writer_options=)

          components
        end

        context 'is enabled' do
          let(:enabled) { true }

          it do
            expect(settings.tracing.test_mode)
              .to have_received(:enabled=)
              .with(true)
          end

          it do
            expect(settings.tracing.test_mode)
              .to have_received(:trace_flush=)
              .with(settings.ci.trace_flush || kind_of(Datadog::CI::Flush::Finished))
          end

          it do
            expect(settings.tracing.test_mode)
              .to have_received(:writer_options=)
              .with(settings.ci.writer_options)
          end
        end

        context 'is disabled' do
          let(:enabled) { false }

          it do
            expect(settings.tracing.test_mode)
              .to_not have_received(:enabled=)
          end

          it do
            expect(settings.tracing.test_mode)
              .to_not have_received(:trace_flush=)
          end

          it do
            expect(settings.tracing.test_mode)
              .to_not have_received(:writer_options=)
          end
        end
      end
    end
  end
end
