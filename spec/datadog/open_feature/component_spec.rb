# frozen_string_literal: true

require 'spec_helper'
require 'open_feature/sdk'
require 'datadog/open_feature/component'
require 'datadog/open_feature/flagevaluation/writer'
require 'datadog/open_feature/hooks/flag_eval_evp_hook'

RSpec.describe Datadog::OpenFeature::Component do
  before do
    allow(Datadog::OpenFeature::Transport::HTTP).to receive(:build).and_return(transport)
    allow(Datadog::OpenFeature::Transport::HTTP).to receive(:build_flagevaluations).and_return(transport)
    allow(Datadog::OpenFeature::Exposures::Worker).to receive(:new).and_return(worker)
    allow(Datadog::OpenFeature::Exposures::Reporter).to receive(:new).and_return(reporter)
    # Never spawn the EVP writer's real background thread in component specs (avoid resource leaks).
    allow_any_instance_of(Datadog::OpenFeature::FlagEvaluation::Writer)
      .to receive(:start_background_thread).and_return(nil)
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { instance_double(Datadog::Core::Configuration::AgentSettings) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }
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

  # The EVP killswitch is read through the config registry (settings.open_feature
  # .evaluation_counts_enabled), NOT raw ENV. When disabled, the EVP hook is not created and the
  # OTel hook is unaffected (non-regression).
  # Hooks only exist when the OpenFeature SDK supports them (>= 0.5); skip on the min appraisal.
  describe 'EVP killswitch via config registry', skip: !Datadog::OpenFeature::Hooks::FlagEvalEVPHook.available? do
    before do
      settings.open_feature.enabled = true
      settings.remote.enabled = true
      stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', nil)
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    context 'when evaluation_counts_enabled is true (default)' do
      it 'creates the EVP hook' do
        expect(component.flag_eval_evp_hook).to be_a(Datadog::OpenFeature::Hooks::FlagEvalEVPHook)
      end

      it 'passes telemetry to the EVP writer' do
        expect(Datadog::OpenFeature::FlagEvaluation::Writer).to receive(:new).with(
          transport: transport,
          logger: logger,
          telemetry: telemetry,
        ).and_call_original

        component
      end
    end

    context 'when evaluation_counts_enabled is false' do
      before { settings.open_feature.evaluation_counts_enabled = false }

      it 'does not create the EVP hook (killswitch), leaving the OTel hook intact' do
        expect(component.flag_eval_evp_hook).to be_nil
        expect(component.flag_eval_hook).to be_a(Datadog::OpenFeature::Hooks::FlagEvalHook)
      end
    end
  end

  describe '#shutdown!' do
    before do
      settings.open_feature.enabled = true
      settings.remote.enabled = true
      stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', nil)
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    it 'gracefully shutdown the worker' do
      expect(worker).to receive(:graceful_shutdown)

      component.shutdown!
    end

    # Shutdown stops the EVP writer (which drains + final-flushes its queue).
    # Only meaningful when the SDK supports hooks (>= 0.5) — skip on the min appraisal.
    it 'stops the EVP flagevaluation writer so it drains and flushes',
      skip: !Datadog::OpenFeature::Hooks::FlagEvalEVPHook.available? do
      evp_writer = component.instance_variable_get(:@flag_eval_evp_writer)
      expect(evp_writer).to be_a(Datadog::OpenFeature::FlagEvaluation::Writer)
      expect(evp_writer).to receive(:stop)
      allow(worker).to receive(:graceful_shutdown)

      component.shutdown!
    end
  end
end
