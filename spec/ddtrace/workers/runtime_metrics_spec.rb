require 'spec_helper'

require 'ddtrace'
require 'ddtrace/workers/runtime_metrics'

RSpec.describe Datadog::Workers::RuntimeMetrics do
  subject(:worker) { described_class.new(options) }

  let(:metrics) { instance_double(Datadog::Runtime::Metrics) }
  let(:options) { { metrics: metrics, enabled: true } }

  before { allow(metrics).to receive(:flush) }

  after { worker.stop(true, 0) }

  describe '#initialize' do
    it { expect(worker).to be_a_kind_of(Datadog::Workers::Polling) }

    context 'by default' do
      subject(:worker) { described_class.new }

      it { expect(worker.enabled?).to be false }
      it { expect(worker.loop_base_interval).to eq 10 }
      it { expect(worker.loop_back_off_ratio).to eq 1.2 }
      it { expect(worker.loop_back_off_max).to eq 30 }
    end

    context 'when :enabled is given' do
      let(:options) { super().merge(enabled: true) }

      it { expect(worker.enabled?).to be true }
    end

    context 'when :enabled is not given' do
      before { options.delete(:enabled) }

      it { expect(worker.enabled?).to be false }
    end

    context 'when :interval is given' do
      let(:value) { double }
      let(:options) { super().merge(interval: value) }

      it { expect(worker.loop_base_interval).to be value }
    end

    context 'when :back_off_ratio is given' do
      let(:value) { double }
      let(:options) { super().merge(back_off_ratio: value) }

      it { expect(worker.loop_back_off_ratio).to be value }
    end

    context 'when :back_off_max is given' do
      let(:value) { double }
      let(:options) { super().merge(back_off_max: value) }

      it { expect(worker.loop_back_off_max).to be value }
    end
  end

  describe '#perform' do
    subject(:perform) { worker.perform }

    after { worker.stop(true, 0) }

    context 'when #enabled? is true' do
      before { allow(worker).to receive(:enabled?).and_return(true) }

      it 'starts a worker thread' do
        perform
        expect(worker).to have_attributes(
          metrics: metrics,
          run_async?: true,
          running?: true,
          started?: true,
          forked?: false,
          fork_policy: Datadog::Workers::Async::Thread::FORK_POLICY_STOP,
          result: nil
        )
      end
    end
  end

  describe '#enabled=' do
    subject(:set_enabled_value) { worker.enabled = value }

    after { worker.stop(true, 0) }

    context 'when not running' do
      before do
        worker.enabled = false
        allow(worker).to receive(:perform)
        allow(worker).to receive(:stop)
      end

      context 'and given true' do
        let(:value) { true }

        it 'starts the worker' do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(false)
            .to(true)

          expect(worker).to_not have_received(:perform)
          expect(worker).to_not have_received(:stop)
        end
      end

      context 'and given false' do
        let(:value) { false }

        it 'does nothing' do
          expect { set_enabled_value }
            .to_not change { worker.enabled? }
            .from(false)

          expect(worker).to_not have_received(:perform)
          expect(worker).to_not have_received(:stop)
        end
      end

      context 'and given nil' do
        let(:value) { nil }

        it 'does nothing' do
          expect { set_enabled_value }
            .to_not change { worker.enabled? }
            .from(false)

          expect(worker).to_not have_received(:perform)
          expect(worker).to_not have_received(:stop)
        end
      end
    end

    context 'when already running' do
      before do
        worker.enabled = true
        allow(worker).to receive(:perform)
        allow(worker).to receive(:stop)
      end

      context 'and given true' do
        let(:value) { true }

        it 'does nothing' do
          expect { set_enabled_value }
            .to_not change { worker.enabled? }
            .from(true)

          expect(worker).to_not have_received(:perform)
          expect(worker).to_not have_received(:stop)
        end
      end

      context 'and given false' do
        let(:value) { false }

        it 'stops the worker' do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(true)
            .to(false)

          expect(worker).to_not have_received(:perform)
          expect(worker).to_not have_received(:stop)
        end
      end

      context 'and given nil' do
        let(:value) { nil }

        it 'stops the worker' do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(true)
            .to(false)

          expect(worker).to_not have_received(:perform)
          expect(worker).to_not have_received(:stop)
        end
      end
    end
  end

  describe '#associate_with_span' do
    subject(:associate_with_span) { worker.associate_with_span(span) }

    let(:span) { instance_double(Datadog::Span) }

    before do
      allow(worker.metrics).to receive(:associate_with_span)
      allow(worker).to receive(:perform)
    end

    it 'forwards to #metrics' do
      associate_with_span

      expect(worker.metrics).to have_received(:associate_with_span)
        .with(span)
      expect(worker).to have_received(:perform)
    end
  end

  describe 'forwarded methods' do
    describe '#register_service' do
      subject(:register_service) { worker.register_service(service) }

      let(:service) { double('service') }

      before { allow(worker.metrics).to receive(:register_service) }

      it 'forwards to #metrics' do
        register_service
        expect(worker.metrics).to have_received(:register_service)
          .with(service)
      end
    end
  end

  describe 'integration tests', :integration do
    describe 'interval' do
      after { worker.stop }

      it 'produces metrics every 10 seconds' do
        worker.perform

        sleep 10.1

        # Metrics are produced once right away
        # and again after 10 seconds.
        expect(metrics).to have_received(:flush).twice
      end
    end

    describe 'forking' do
      before { skip unless PlatformHelpers.supports_fork? }

      let(:options) do
        {
          metrics: metrics,
          fork_policy: fork_policy,
          enabled: true
        }
      end

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
