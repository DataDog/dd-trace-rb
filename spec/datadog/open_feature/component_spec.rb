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
  let(:agent_settings) { instance_double(Datadog::Core::Configuration::AgentSettings) }
  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::Exposures::Transport) }
  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }

  describe '.build' do
    subject(:component) do
      described_class.build(settings, agent_settings, logger: logger, telemetry: telemetry)
    end

    context 'when open_feature is enabled' do
      before { settings.open_feature.enabled = true }

      context 'when remote configuration is enabled' do
        before { settings.remote.enabled = true }

        it 'returns configured component instance' do
          expect(component).to be_a(described_class)
          expect(component.engine).to be_a(Datadog::OpenFeature::EvaluationEngine)
          expect(Datadog::OpenFeature::Exposures::Reporter).to have_received(:new)
        end
      end

      context 'when remote configuration is disabled' do
        before { settings.remote.enabled = false }

        it 'logs warning and returns nil' do
          expect(logger).to receive(:warn)
            .with(/could not be enabled as Remote Configuration is currently disabled/)

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
  end

  describe '#flush' do
    before do
      settings.open_feature.enabled = true
      settings.remote.enabled = true
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    it 'flushes worker' do
      expect(worker).to receive(:flush)

      component.flush
    end
  end

  describe '#shutdown!' do
    before do
      settings.open_feature.enabled = true
      settings.remote.enabled = true
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    it 'gracefully shutdown the worker' do
      expect(worker).to receive(:graceful_shutdown)

      component.shutdown!
    end
  end
end
