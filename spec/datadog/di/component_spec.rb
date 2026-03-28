require "datadog/di/spec_helper"
require 'datadog/di/component'

RSpec.describe Datadog::DI::Component do
  di_test

  describe '.build' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.internal.development = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    let(:logger) do
      instance_double(Logger)
    end

    context 'when remote config is enabled' do
      before do
        settings.remote.enabled = true
      end

      it 'returns a Component in stopped state' do
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be_a(described_class)
        expect(component.started?).to be false
        component.shutdown!
      end
    end

    context 'when remote config is disabled' do
      before do
        settings.remote.enabled = false
      end

      it 'returns nil' do
        expect(logger).to receive(:debug)
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be nil
      end
    end

    context 'when C extension is not available' do
      before do
        settings.remote.enabled = true
        allow(Datadog::DI).to receive(:respond_to?).and_call_original
        allow(Datadog::DI).to receive(:respond_to?).with(:exception_message).and_return(false)
      end

      it 'returns nil' do
        expect(logger).to receive(:debug)
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be nil
      end
    end

    context 'regardless of DD_DYNAMIC_INSTRUMENTATION_ENABLED' do
      before do
        settings.remote.enabled = true
        settings.dynamic_instrumentation.enabled = false
      end

      it 'still builds the component' do
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be_a(described_class)
        expect(component.started?).to be false
        component.shutdown!
      end
    end
  end

  describe '#start! and #stop!' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.internal.development = true
      settings.remote.enabled = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    let(:logger) do
      instance_double(Logger)
    end

    let(:component) do
      described_class.build(settings, agent_settings, logger)
    end

    after do
      component&.shutdown!
    end

    it 'starts and stops the component' do
      expect(component.started?).to be false
      component.start!
      expect(component.started?).to be true
      component.stop!
      expect(component.started?).to be false
    end

    it 'start! is idempotent' do
      component.start!
      component.start!
      expect(component.started?).to be true
    end

    it 'stop! is idempotent' do
      component.stop!
      component.stop!
      expect(component.started?).to be false
    end

    it 'supports restart after stop' do
      component.start!
      expect(component.started?).to be true
      component.stop!
      expect(component.started?).to be false
      component.start!
      expect(component.started?).to be true
    end

    it 'does not have background threads when stopped' do
      threads_before = Thread.list.size
      # Component is built but stopped — no new threads
      expect(Thread.list.size).to eq(threads_before)
    end

    it 'definition trace point is disabled when stopped' do
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be false
    end

    it 'definition trace point is enabled after start' do
      component.start!
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be true
    end

    it 'definition trace point is disabled after stop' do
      component.start!
      component.stop!
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be false
    end

    it 'definition trace point is re-enabled after restart' do
      component.start!
      component.stop!
      component.start!
      expect(component.probe_manager.send(:definition_trace_point).enabled?).to be true
    end
  end

  describe '#parse_probe_spec_and_notify' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.remote.enabled = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    let(:logger) do
      instance_double(Logger)
    end

    let(:telemetry) do
      instance_double(Datadog::Core::Telemetry::Component)
    end

    let(:component) do
      described_class.build(settings, agent_settings, logger, telemetry: telemetry).tap(&:start!)
    end

    let(:probe_spec) do
      {
        'id' => 'test-probe-id',
        'type' => 'LOG_PROBE',
      }
    end

    after do
      component&.shutdown!
    end

    context 'when building error notification fails' do
      it 'reports exception to telemetry' do
        allow(logger).to receive(:debug)

        # Make ProbeBuilder raise an error
        expect(Datadog::DI::ProbeBuilder).to receive(:build_from_remote_config).and_raise(StandardError, "probe build error")

        # Make the error notification building also fail
        expect(component.probe_notification_builder).to receive(:build_errored).and_raise(RuntimeError, "notification build error")

        expect(telemetry).to receive(:report) do |exc, description:|
          expect(exc).to be_a(RuntimeError)
          expect(exc.message).to eq("notification build error")
          expect(description).to eq("Error building probe error notification")
        end

        expect do
          component.parse_probe_spec_and_notify(probe_spec)
        end.to raise_error(RuntimeError, "notification build error")
      end
    end
  end
end
