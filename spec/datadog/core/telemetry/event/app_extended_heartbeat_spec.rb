# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/event/app_extended_heartbeat'

RSpec.describe Datadog::Core::Telemetry::Event::AppExtendedHeartbeat do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings) }
  let(:event) { described_class.new(settings: settings, agent_settings: agent_settings) }

  describe '#type' do
    it { expect(event.type).to eq('app-extended-heartbeat') }
  end

  describe '#app_started?' do
    it { expect(event.app_started?).to be(false) }
  end

  describe '#payload' do
    subject(:payload) { event.payload }

    it 'includes only configuration' do
      expect(payload.keys).to eq([:configuration])
    end

    it 'includes a non-empty configuration array' do
      expect(payload[:configuration]).to be_a(Array)
      expect(payload[:configuration]).not_to be_empty
    end

    it 'reflects settings values at instantiation time' do
      settings.service = 'my-service'
      event = described_class.new(settings: settings, agent_settings: agent_settings)

      expect(event.payload[:configuration]).to include(
        hash_including(name: 'DD_SERVICE', value: 'my-service')
      )
    end

    it 'picks up changes made after a prior instantiation' do
      settings.service = 'before'
      _old_event = described_class.new(settings: settings, agent_settings: agent_settings)

      settings.service = 'after'
      new_event = described_class.new(settings: settings, agent_settings: agent_settings)

      expect(new_event.payload[:configuration]).to include(
        hash_including(name: 'DD_SERVICE', value: 'after')
      )
    end
  end
end
