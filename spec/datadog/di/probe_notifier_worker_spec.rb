require "datadog/di/spec_helper"
require "datadog/di/probe_notifier_worker"

RSpec.describe Datadog::DI::ProbeNotifierWorker do
  di_test

  let(:settings) do
    double('settings').tap do |settings|
      allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
    end
  end

  let(:di_settings) do
    double('di settings').tap do |settings|
      allow(settings).to receive(:propagate_all_exceptions).and_return(false)
    end
  end

  let(:agent_settings) do
    double('agent settings')
  end

  let(:transport) do
    double('transport')
  end

  let(:worker) { described_class.new(settings, agent_settings, transport) }

  context 'not started' do
    describe '#add_snapshot' do
      let(:snapshot) do
        {hello: 'world'}
      end

      it 'adds snapshot to queue' do
        expect(worker.send(:snapshot_queue)).to be_empty

        worker.add_snapshot(snapshot)

        expect(worker.send(:snapshot_queue)).to eq([snapshot])
      end
    end
  end

  describe '#stop' do
    before do
      worker.start
    end

    it 'stops the thread' do
      worker.stop
      expect(worker.send(:thread)).to be nil
    end
  end

  context 'started' do
    before do
      worker.start
    end

    after do
      worker.stop
    end

    describe '#add_snapshot' do
      let(:snapshot) do
        {hello: 'world'}
      end

      it 'sends the snapshot' do
        expect(worker.send(:snapshot_queue)).to be_empty

        expect(transport).to receive(:send_snapshot).once.with([snapshot])

        worker.add_snapshot(snapshot)

        # Since sending is asynchronous, we need to relinquish execution
        # for the sending thread to run.
        sleep(0.1)

        expect(worker.send(:snapshot_queue)).to eq([])
      end

      context 'when three snapshots are added in quick succession' do
        it 'sends two batches' do
          expect(worker.send(:snapshot_queue)).to be_empty

          expect(transport).to receive(:send_snapshot).once.with([snapshot])

          worker.add_snapshot(snapshot)
          sleep 0.1
          worker.add_snapshot(snapshot)
          sleep 0.1
          worker.add_snapshot(snapshot)

          # Since sending is asynchronous, we need to relinquish execution
          # for the sending thread to run.
          sleep(0.1)

          # At this point the first snapshot should have been sent,
          # with the remaining two in the queue
          expect(worker.send(:snapshot_queue)).to eq([snapshot, snapshot])

          sleep 0.4
          # Still within the cooldown period
          expect(worker.send(:snapshot_queue)).to eq([snapshot, snapshot])

          expect(transport).to receive(:send_snapshot).once.with([snapshot, snapshot])

          sleep 0.5
          expect(worker.send(:snapshot_queue)).to eq([])
        end
      end
    end
  end
end
