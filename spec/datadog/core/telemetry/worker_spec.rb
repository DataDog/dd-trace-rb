require 'spec_helper'

require 'datadog/core/telemetry/worker'

RSpec.describe Datadog::Core::Telemetry::Worker do
  subject(:worker) do
    described_class.new(enabled: enabled, heartbeat_interval_seconds: heartbeat_interval_seconds, emitter: emitter)
  end

  let(:enabled) { true }
  let(:heartbeat_interval_seconds) { 1.2 }
  let(:emitter) { double(Datadog::Core::Telemetry::Emitter) }

  before do
    allow(emitter).to receive(:request)
  end

  after do
    worker.stop(true, 0)
    worker.join
  end

  describe '.new' do
    it 'creates a new worker in stopped state' do
      expect(worker).to have_attributes(
        enabled?: true,
        loop_base_interval: 1.2, # seconds
        run_async?: false,
        running?: false,
        started?: false
      )
    end
  end

  describe '#start' do
    context 'when enabled' do
      it 'starts the worker and sends heartbeat event' do
        worker.start

        try_wait_until { worker.running? }

        expect(worker).to have_attributes(
          enabled?: true,
          loop_base_interval: 1.2, # seconds
          run_async?: true,
          running?: true,
          started?: true
        )
        expect(emitter).to have_received(:request).with(an_instance_of(Datadog::Core::Telemetry::Event::AppHeartbeat))
      end
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does not start the worker' do
        expect(worker).not_to receive(:perform)

        worker.start
      end
    end
  end
end
