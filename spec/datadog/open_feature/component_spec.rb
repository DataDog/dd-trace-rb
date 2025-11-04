# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/component'

RSpec.describe Datadog::OpenFeature::Component do
  before do
    allow(logger).to receive(:warn)
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { instance_double(Datadog::Core::Configuration::AgentSettings) }
  let(:logger) { instance_double(Logger) }

  describe '.build' do
    subject(:component) do
      described_class.build(settings, agent_settings, logger: logger, telemetry: telemetry)
    end

    context 'when open_feature is enabled' do
      before do
        settings.open_feature.enabled = true
      end

      context 'when remote configuration is enabled' do
        before { settings.remote.enabled = true }

        it 'returns configured component instance' do
          expect(component).to be_a(described_class)
          expect(component.engine).to be_a(Datadog::OpenFeature::EvaluationEngine)
        end
      end

      context 'when remote configuration is disabled' do
        before { settings.remote.enabled = false }

        it 'logs warning and returns nil' do
          expect(logger).to receive(:warn)
            .with(/Could not be enabled without Remote Configuration Management/)

          expect(component).to be_nil
        end
      end

      context 'when exception happens during initialization' do
        before do
          settings.remote.enabled = true
          allow(Datadog::OpenFeature::EvaluationEngine).to receive(:new).and_raise('Error!')
        end

        it 'logs warning and disables the component' do
          expect(Datadog.logger).to receive(:warn).with(/OpenFeature is disabled/)
          expect(component).to be_nil
        end
      end
    end

    context 'when open_feature is not enabled' do
      before { settings.open_feature.enabled = false }

      it { expect(component).to be_nil }
    end

    context 'when settings does not include open_feature' do
      before { allow(settings).to receive(:respond_to?).and_return(false) }

      let(:settings) { instance_double(Datadog::Core::Configuration::Settings) }

      it { expect(component).to be_nil }
    end
  end
end
