require "datadog/di/spec_helper"
require "datadog/di/probe_notifier_worker"
require 'logger'

RSpec.describe Datadog::DI::ProbeNotifierWorker do
  di_test

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(false)
    # Reduce to 1 to have the test run faster
    allow(settings.dynamic_instrumentation.internal).to receive(:min_send_interval).and_return(1)
    allow(settings.dynamic_instrumentation.internal).to receive(:snapshot_queue_capacity).and_return(10)
  end

  let(:agent_settings) do
    instance_double_agent_settings
  end

  di_logger_double

  let(:worker) { described_class.new(settings, logger, agent_settings: agent_settings) }

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
  end

  after do
    worker.stop
  end

  context 'not started' do
    describe '#add_snapshot' do
      let(:snapshot) do
        {hello: 'world'}
      end

      it 'adds snapshot to queue' do
        # Depending on scheduling, the worker thread may attempt to
        # invoke the transport to send the snapshot.
        allow(input_transport).to receive(:send_input)

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

        expect(input_transport).to receive(:send_input).once.with([snapshot])

        worker.add_snapshot(snapshot)

        worker.flush

        expect(worker.send(:snapshot_queue)).to eq([])
      end

      context 'when three snapshots are added in quick succession' do
        it 'sends two batches' do
          expect(worker.send(:snapshot_queue)).to be_empty

          expect(input_transport).to receive(:send_input).once.with([snapshot])

          worker.add_snapshot(snapshot)
          sleep 0.1
          worker.add_snapshot(snapshot)
          sleep 0.1
          worker.add_snapshot(snapshot)
          sleep(0.1)

          # At this point the first snapshot should have been sent,
          # with the remaining two in the queue
          expect(worker.send(:snapshot_queue)).to eq([snapshot, snapshot])

          expect(input_transport).to receive(:send_input).once.with([snapshot, snapshot])

          worker.flush
          expect(worker.send(:snapshot_queue)).to eq([])
        end
      end
    end
  end
end
