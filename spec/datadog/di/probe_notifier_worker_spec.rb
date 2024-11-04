require "datadog/di/spec_helper"
require "datadog/di/probe_notifier_worker"

RSpec.describe Datadog::DI::ProbeNotifierWorker do
  di_test

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(false)
    # Reduce to 1 to have the test run faster
    allow(settings.dynamic_instrumentation.internal).to receive(:min_send_interval).and_return(1)
  end

  let(:transport) do
    double('transport')
  end

  let(:logger) do
    instance_double(Logger)
  end

  let(:worker) { described_class.new(settings, transport, logger) }

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
    context 'worker is running' do
      before do
        worker.start
      end

      it 'stops the thread' do
        worker.stop
        expect(worker.send(:thread)).to be nil
      end
    end

    context 'worker is not running' do
      before do
        expect(worker.send(:thread)).to be nil
      end

      it 'does nothing and raises no exceptions' do
        expect do
          worker.stop
        end.not_to raise_error
      end
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

        worker.flush

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
          sleep(0.1)

          # At this point the first snapshot should have been sent,
          # with the remaining two in the queue
          expect(worker.send(:snapshot_queue)).to eq([snapshot, snapshot])

          expect(transport).to receive(:send_snapshot).once.with([snapshot, snapshot])

          worker.flush
          expect(worker.send(:snapshot_queue)).to eq([])
        end
      end
    end
  end
end
