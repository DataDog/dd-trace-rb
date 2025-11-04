# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/component'

RSpec.describe Datadog::OpenFeature::Component do
  let(:component) { described_class.build_open_feature_component(settings, telemetry: telemetry) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }

  describe '.build_open_feature_component' do
    context 'when open_feature is enabled' do
      before { settings.open_feature.enabled = true }

      it 'returns configured component instance' do
        expect(component).to be_a(described_class)
        expect(component.engine).to be_a(Datadog::OpenFeature::EvaluationEngine)
      end
    end

    context 'when open_feature is not enabled' do
      before { settings.open_feature.enabled = false }

      it { expect(component).to be_nil }
    end

    context 'when exception happens during initialization' do
      before do
        settings.open_feature.enabled = true
        allow(Datadog::OpenFeature::EvaluationEngine).to receive(:new).and_raise('Error!')
      end

      it 'logs warning and disables the component' do
        expect(Datadog.logger).to receive(:warn).with(/OpenFeature is disabled/)

        expect(component).to be_nil
      end
    end

    context 'when settings does not include open_feature' do
      let(:settings) { instance_double(Datadog::Core::Configuration::Settings) }

      it { expect(component).to be_nil }
    end
  end
end
