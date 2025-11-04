# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/component'

RSpec.describe Datadog::OpenFeature::Component do
  before do
    allow(Datadog::OpenFeature::Transport::HTTP).to receive(:build).and_return(transport)
    allow(Datadog::OpenFeature::Exposures::Worker).to receive(:new).and_return(worker)
    allow(Datadog::OpenFeature::Exposures::Reporter).to receive(:new).and_return(reporter)
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }

  describe '.build_open_feature_component' do
    subject(:component) do
      described_class.build_open_feature_component(settings, telemetry: telemetry)
    end

    context 'when open_feature is enabled' do
      before do
        settings.open_feature.enabled = true
      end

      context 'when remote configuration is disabled' do
        before { settings.remote.enabled = false }

        it 'logs warning and returns nil' do
          expect(logger).to receive(:warn)
            .with(/could not be enabled without Remote Configuration/)

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
      before { allow(settings).to receive(:respond_to?).with(:open_feature).and_return(false) }

      it { expect(component).to be_nil }
    end
  end

  describe '#shutdown!' do
    subject(:component) { described_class.new(telemetry: telemetry) }

    it 'is a no-op' do
      expect { component.shutdown! }.not_to raise_error
    end
  end
end
