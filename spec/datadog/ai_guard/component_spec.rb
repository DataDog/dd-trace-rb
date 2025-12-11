# frozen_string_literal: true

require 'datadog/ai_guard/component'

RSpec.describe Datadog::AIGuard::Component do
  describe '.build' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }
    let(:logger) { instance_double(Datadog::Core::Logger) }
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    context 'when AI Guard is enabled' do
      before do
        settings.ai_guard.enabled = true
      end

      it 'returns component instance with initialized API client' do
        component = described_class.build(settings, logger: logger, telemetry: telemetry)

        expect(component.api_client).not_to be_nil
      end
    end

    context 'when AI Guard is disabled' do
      before do
        settings.ai_guard.enabled = false
      end

      it 'returns nil' do
        expect(described_class.build(settings, logger: logger, telemetry: telemetry)).to be_nil
      end
    end
  end
end
