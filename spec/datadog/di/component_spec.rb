require "datadog/di/spec_helper"
require 'datadog/di/component'

RSpec.describe Datadog::DI::Component do
  di_test

  describe '.build' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.dynamic_instrumentation.enabled = dynamic_instrumentation_enabled
      settings.dynamic_instrumentation.internal.development = true
      settings
    end

    let(:agent_settings) do
      instance_double_agent_settings
    end

    let(:logger) do
      instance_double(Logger)
    end

    context 'when dynamic instrumentation is enabled' do
      let(:dynamic_instrumentation_enabled) { true }

      let(:agent_settings) do
        instance_double_agent_settings_with_stubs
      end

      context 'when remote config is enabled' do
        before do
          settings.remote.enabled = true
        end

        it 'returns a Datadog::DI::Component instance' do
          component = described_class.build(settings, agent_settings, logger)
          expect(component).to be_a(described_class)
          component.shutdown!
        end
      end

      context 'when remote config is disabled' do
        before do
          settings.remote.enabled = false
        end

        it 'returns nil' do
          expect(logger).to receive(:warn).with(/dynamic instrumentation could not be enabled because Remote Configuration Management is not available/)
          component = described_class.build(settings, agent_settings, logger)
          expect(component).to be nil
        end
      end
    end

    context 'when dynamic instrumentation is disabled' do
      let(:dynamic_instrumentation_enabled) { false }

      it 'returns nil' do
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be nil
      end
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
      described_class.build(settings, agent_settings, logger, telemetry: telemetry)
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
