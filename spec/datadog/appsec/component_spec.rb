require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }

  describe '.build_appsec_component' do
    context 'when appsec is enabled' do
      before do
        settings.appsec.enabled = true
        allow(telemetry).to receive(:inc)
      end

      it 'returns a Datadog::AppSec::Component instance' do
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        expect(component).to be_a(described_class)
      end

      context 'when using ffi version that is known to leak memory with Ruby >= 3.3.0' do
        before do
          stub_const('RUBY_VERSION', '3.3.0')
          allow(Gem).to receive(:loaded_specs).and_return('ffi' => double(version: Gem::Version.new('1.15.4')))
        end

        it 'returns nil, warns and reports telemetry' do
          expect(Datadog.logger).to receive(:warn)
          expect(telemetry).to receive(:error)
            .with('AppSec: Component not loaded, ffi version is leaky with ruby > 3.3.0')

          component = described_class.build_appsec_component(settings, telemetry: telemetry)
          expect(component).to be_nil
        end
      end

      context 'when ffi is not loaded' do
        before { allow(Gem).to receive(:loaded_specs).and_return({}) }

        it 'returns nil, warns and reports telemetry' do
          expect(Datadog.logger).to receive(:warn)
          expect(telemetry).to receive(:error).with('AppSec: Component not loaded, due to missing FFI gem')

          component = described_class.build_appsec_component(settings, telemetry: telemetry)
          expect(component).to be_nil
        end
      end

      it 'returns nil when security engine fails to instantiate' do
        settings.appsec.ruleset = {}

        allow(telemetry).to receive(:inc)
        expect(telemetry).to receive(:report)
        expect(Datadog.logger).to receive(:warn)

        expect(described_class.build_appsec_component(settings, telemetry: telemetry)).to be_nil
      end
    end

    context 'when appsec is not enabled' do
      before do
        settings.appsec.enabled = false
      end

      it 'returns nil' do
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        expect(component).to be_nil
      end
    end

    context 'when appsec is not active' do
      it 'returns nil' do
        component = described_class.build_appsec_component(
          double(Datadog::Core::Configuration::Settings),
          telemetry: telemetry
        )
        expect(component).to be_nil
      end
    end
  end
end
