require 'spec_helper'

require 'datadog/core/telemetry/worker'

RSpec.describe Datadog::Core::Telemetry::Worker do
  subject(:worker) do
    described_class.new(enabled: enabled, heartbeat_interval_seconds: heartbeat_interval_seconds, &block)
  end

  let(:enabled) { true }
  let(:heartbeat_interval_seconds) { 1.2 }
  let(:block) { proc {} }

  after do
    worker.stop(true)
    worker.join
  end

  describe '.new' do
    context 'when enabled' do
      let(:enabled) { true }

      it do
        worker

        try_wait_until { worker.running? }
        expect(worker).to have_attributes(
          run_async?: true,
          running?: true,
          started?: true
        )
      end
    end
  end
end
