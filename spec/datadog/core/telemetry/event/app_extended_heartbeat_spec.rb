# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/event/app_extended_heartbeat'

RSpec.describe Datadog::Core::Telemetry::Event::AppExtendedHeartbeat do
  let(:configuration) do
    [
      {name: 'DD_TRACE_ENABLED', value: 'true', origin: 'default', seq_id: 1},
      {name: 'DD_ENV', value: 'production', origin: 'env_var', seq_id: 1},
    ]
  end
  let(:event) { described_class.new(configuration: configuration) }

  describe '#type' do
    it { expect(event.type).to eq('app-extended-heartbeat') }
  end

  describe '#payload' do
    subject(:payload) { event.payload }

    it 'includes configuration' do
      expect(payload[:configuration]).to eq(configuration)
    end

    it 'has the same configuration as provided' do
      expect(payload[:configuration].size).to eq(2)
      expect(payload[:configuration].first[:name]).to eq('DD_TRACE_ENABLED')
    end
  end
end
