require 'spec_helper'

require 'datadog/core/worker'
require 'datadog/core/workers/polling'

RSpec.describe Datadog::Core::Workers::Polling do
  context 'when included into a worker' do
    subject(:worker) { worker_class.new }

    let(:worker_class) do
      Class.new(Datadog::Core::Worker) { include Datadog::Core::Workers::Polling }
    end

    describe '#perform' do
      subject(:perform) { worker.perform }

      after { worker.stop(true, 5) }

      let(:worker) { worker_class.new(&task) }
      let(:task) { proc { |*args| worker_spy.perform(*args) } }
      let(:worker_spy) { double('worker spy') }

      before { allow(worker_spy).to receive(:perform) }

      context 'when #enabled? is true' do
        before { allow(worker).to receive(:enabled?).and_return(true) }

        it do
          perform
          wait_for(worker_spy).to have_received(:perform)
        end
      end

      context 'when #enabled? is false' do
        before { allow(worker).to receive(:enabled?).and_return(false) }

        it do
          perform
          expect(worker_spy).to_not have_received(:perform)
        end
      end
    end

    describe '#stop' do
      subject(:stop) { worker.stop }

      shared_context 'graceful stop' do
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
        include_context 'graceful stop'

        before do
          worker.perform
          try_wait_until { worker.running? && worker.run_loop? }
        end

        it { is_expected.to be true }
      end

      context 'called multiple times with graceful stop' do
        include_context 'graceful stop'

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

    describe '#enabled?' do
      subject(:enabled?) { worker.enabled? }

      before { allow(worker).to receive(:perform) }

      context 'by default' do
        it { is_expected.to be true }
      end

      context 'when enabled= is set to false' do
        it do
          expect { worker.enabled = false }
            .to change { worker.enabled? }
            .from(true)
            .to(false)
        end
      end
    end

    describe '#enabled=' do
      subject(:set_enabled_value) { worker.enabled = value }

      context 'and given true' do
        let(:value) { true }

        it do
          expect { set_enabled_value }
            .to_not change { worker.enabled? }
            .from(true)
        end
      end

      context 'and given false' do
        let(:value) { false }

        it do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(true)
            .to(false)
        end
      end

      context 'and given nil' do
        let(:value) { nil }

        it 'does nothing' do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(true)
            .to(false)
        end
      end
    end
  end
end
