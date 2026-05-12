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

      it 'returns nil when security engine fails to instantiate' do
        settings.appsec.ruleset = {}

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
