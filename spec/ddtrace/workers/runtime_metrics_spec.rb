require 'spec_helper'

require 'ddtrace'
require 'ddtrace/workers/runtime_metrics'

RSpec.describe Datadog::Workers::RuntimeMetrics do
  subject(:worker) { described_class.new(metrics, options) }
  let(:metrics) { instance_double(Datadog::Runtime::Metrics) }
  let(:options) { {} }

  before { allow(metrics).to receive(:flush) }

  describe '#perform' do
    subject(:perform) { worker.perform }
    after { worker.stop(true, 0) }

    it 'starts a worker thread' do
      perform
      expect(worker).to have_attributes(
        metrics: metrics,
        run_async?: true,
        running?: true,
        unstarted?: false,
        forked?: false,
        fork_policy: :stop,
        result: nil
      )
    end
  end

  describe '#stop' do
    subject(:stop) { worker.stop }

    shared_context 'shuts down the worker' do
      before do
        allow(worker).to receive(:join)
          .with(described_class::SHUTDOWN_TIMEOUT)
          .and_return(true)
      end
    end

    context 'when the worker has not been started' do
      before do
        allow(worker).to receive(:join)
          .with(described_class::SHUTDOWN_TIMEOUT)
          .and_return(true)
      end

      it { is_expected.to be false }
    end

    context 'when the worker has been started' do
      include_context 'shuts down the worker'

      before do
        worker.perform
        try_wait_until { worker.running? && worker.run_loop? }
      end

      it { is_expected.to be true }
    end

    context 'called multiple times with graceful stop' do
      include_context 'shuts down the worker'

      before do
        worker.perform
        try_wait_until { worker.running? && worker.run_loop? }
      end

      it do
        expect(worker.stop).to be true
        try_wait_until { !worker.running? }
        expect(worker.stop).to be false
      end
    end

    context 'given force_stop: true' do
      subject(:stop) { worker.stop(true) }

      context 'and the worker does not gracefully stop' do
        before do
          # Make it ignore graceful stops
          allow(worker).to receive(:stop_loop).and_return(false)
          allow(worker).to receive(:join).and_return(nil)
        end

        context 'after the worker has been started' do
          before { worker.perform }

          it do
            is_expected.to be true

            # Give thread time to be terminated
            try_wait_until { !worker.running? }

            expect(worker.run_async?).to be false
            expect(worker.running?).to be false
          end
        end
      end
    end
  end

  describe 'integration tests' do
    let(:options) { { fork_policy: fork_policy } }

    before do
      allow(Datadog.configuration).to receive(:runtime_metrics_enabled)
        .and_return(true)
    end

    describe 'forking' do
      context 'when the process forks' do
        before { allow(metrics).to receive(:flush) }
        after { worker.stop }

        context 'with FORK_POLICY_STOP fork policy' do
          let(:fork_policy) { Datadog::Workers::Async::Thread::FORK_POLICY_STOP }

          it 'does not produce metrics' do
            # Start worker in main process
            worker.perform

            expect_in_fork do
              # Capture the flush
              @flushed = false
              allow(metrics).to receive(:flush) do
                @flushed = true
              end

              # Attempt restart of worker & verify it stops.
              expect { worker.perform }.to change { worker.run_async? }
                .from(true)
                .to(false)
            end
          end
        end

        context 'with FORK_POLICY_RESTART fork policy' do
          let(:fork_policy) { Datadog::Workers::Async::Thread::FORK_POLICY_RESTART }

          it 'continues producing metrics' do
            # Start worker
            worker.perform

            expect_in_fork do
              # Capture the flush
              @flushed = false
              allow(metrics).to receive(:flush) do
                @flushed = true
              end

              # Restart worker & wait
              worker.perform
              try_wait_until(attempts: 30) { @flushed }

              # Verify state of the worker
              expect(worker.error?).to be false
              expect(metrics).to have_received(:flush).at_least(:once)
            end
          end
        end
      end
    end
  end
end
