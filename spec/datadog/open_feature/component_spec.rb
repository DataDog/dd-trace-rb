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
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }

  describe '.build' do
    subject(:component) do
      described_class.build(settings, agent_settings, logger: logger, telemetry: telemetry)
    end

    context 'when open_feature is enabled' do
      before { settings.open_feature.enabled = true }

      context 'when remote configuration is enabled' do
        before do
          stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', nil)
          settings.remote.enabled = true
        end

        it 'returns configured component instance' do
          expect(component).to be_a(described_class)
          expect(component.engine).to be_a(Datadog::OpenFeature::EvaluationEngine)

          expect(Datadog::OpenFeature::Exposures::Reporter).to have_received(:new)
        end

        context 'when libdatadog is unavailable' do
          before { stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'Failed to load') }

          it 'logs warning and returns nil' do
            expect(logger).to receive(:warn).with(/`libdatadog` is not loaded: "Failed to load"/)

            expect(component).to be_nil
          end
        end

        context 'when not running on MRI' do
          before { stub_const('RUBY_ENGINE', 'jruby') }

          it 'logs warning and returns nil' do
            expect(logger).to receive(:warn).with(/MRI is required, but running on "jruby"/)

            expect(component).to be_nil
          end
        end
      end

      context 'when remote configuration is disabled' do
        before { settings.remote.enabled = false }

        it 'logs warning and returns nil' do
          expect(logger).to receive(:warn).with(/Remote Configuration is currently disabled/)

          expect(component).to be_nil
        end
      end
    end

    context 'when open_feature is not enabled' do
      before { settings.open_feature.enabled = false }

      it { expect(component).to be_nil }
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
