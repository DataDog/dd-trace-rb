require 'spec_helper'

require 'datadog/core/telemetry/heartbeat'

RSpec.describe Datadog::Core::Telemetry::Heartbeat do
  subject(:heartbeat) do
    described_class.new(enabled: enabled, heartbeat_interval_seconds: heartbeat_interval_seconds, &block)
  end

  let(:enabled) { true }
  let(:heartbeat_interval_seconds) { 1.2 }
  let(:block) { proc {} }

  after do
    heartbeat.stop(true, 0)
    heartbeat.join
  end

  describe '.new' do
    context 'when using default settings' do
      subject(:heartbeat) { described_class.new(heartbeat_interval_seconds: heartbeat_interval_seconds, &block) }
      it do
        is_expected.to have_attributes(
          enabled?: true,
          loop_base_interval: 1.2, # seconds
          task: block
        )
      end
    end

    context 'when enabled' do
      let(:enabled) { true }

      it do
        heartbeat

        try_wait_until { heartbeat.running? }
        expect(heartbeat).to have_attributes(
          run_async?: true,
          running?: true,
          started?: true
        )
      end
    end
  end
end
