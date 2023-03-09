require 'spec_helper'

require 'datadog/core/worker'
require 'datadog/core/workers/interval_loop'

RSpec.describe Datadog::Core::Workers::IntervalLoop do
  context 'when included into a worker' do
    subject(:worker) { worker_class.new(&task) }

    let(:worker_class) do
      Class.new(Datadog::Core::Worker) { include Datadog::Core::Workers::IntervalLoop }
    end

    let(:task) { proc { |*args| worker_spy.perform(*args) } }
    let(:worker_spy) { double('worker spy') }

    before do
      allow(worker_spy).to receive(:perform)
      allow(worker.send(:shutdown)).to receive(:wait) # Stub conditional wait so tests run faster
    end

    shared_context 'loop limit' do
      let(:perform_limit) { 2 }

      before do
        @perform_invocations ||= 0

        allow(worker_spy).to receive(:perform) do |*actual_args|
          expect(actual_args).to eq args

          # Abort loop if limit reached
          @perform_invocations += 1
          worker.stop_loop if @perform_invocations >= perform_limit
        end
      end
    end

    shared_context 'perform loop in thread' do
      before do
        # Start the loop in a thread, give it time to warm up.
        @thread = Thread.new { worker.perform }
        sleep(0.1)
      end

      after do
        @thread.kill
        @thread.join
      end
    end

    describe '#perform' do
      subject(:perform) { worker.perform(*args) }

      let(:args) { [:foo, :bar] }

      context 'given arguments' do
        include_context 'loop limit'

        it 'performs the loop' do
          perform
          expect(@perform_invocations).to eq(perform_limit)
        end
      end

      it 'executes the task BEFORE the first sleep' do
        perform_executed = false
        allow(worker_spy).to receive(:perform) { perform_executed = true }

        expect(worker.send(:shutdown)).to receive(:wait) {
          expect(perform_executed).to be true
          allow(worker_spy).to receive(:perform) { worker.stop_loop }
        }

        perform
      end

      context 'when #loop_wait_before_first_iteration? is true' do
        before do
          allow(worker).to receive(:loop_wait_before_first_iteration?).and_return(true)
        end

        it 'executes the task AFTER the first sleep' do
          perform_executed = false
          allow(worker_spy).to receive(:perform) { perform_executed = true }

          expect(worker.send(:shutdown)).to receive(:wait) {
            expect(perform_executed).to be false
            allow(worker_spy).to receive(:perform) { worker.stop_loop }
          }

          perform
        end
      end
    end

    describe '#stop_loop' do
      subject(:stop_loop) { worker.stop_loop }

      context 'when the worker is not running' do
        before { worker.stop_loop }

        it { is_expected.to be false }
      end

      context 'when the worker is running' do
        include_context 'perform loop in thread'

        it { is_expected.to be true }

        it do
          expect { stop_loop }.to change { worker.run_loop? }
            .from(true)
            .to(false)
        end

        it do
          expect { stop_loop }.to change { worker.work_pending? }
            .from(true)
            .to(false)
        end
      end
    end

    describe '#work_pending?' do
      subject(:work_pending?) { worker.work_pending? }

      context 'when the worker is not running' do
        it { is_expected.to be false }
      end

      context 'when the worker is running' do
        include_context 'perform loop in thread'
        it { is_expected.to be true }
      end
    end

    describe '#run_loop?' do
      subject(:run_loop?) { worker.run_loop? }

      context 'when worker is not running' do
        it { is_expected.to be false }
      end

      context 'when worker is running' do
        include_context 'perform loop in thread'
        it { is_expected.to be true }
      end
    end

    describe '#loop_base_interval' do
      subject(:loop_base_interval) { worker.loop_base_interval }

      context 'default' do
        it { is_expected.to eq(described_class::BASE_INTERVAL) }
      end

      context 'when set' do
        let(:value) { rand }

        it do
          expect { worker.send(:loop_base_interval=, value) }
            .to change { worker.loop_base_interval }
            .from(described_class::BASE_INTERVAL)
            .to(value)
        end
      end
    end

    describe '#loop_back_off_ratio' do
      subject(:loop_back_off_ratio) { worker.loop_back_off_ratio }

      context 'default' do
        it { is_expected.to eq(described_class::BACK_OFF_RATIO) }
      end

      context 'when set' do
        let(:value) { rand }

        it do
          expect { worker.send(:loop_back_off_ratio=, value) }
            .to change { worker.loop_back_off_ratio }
            .from(described_class::BACK_OFF_RATIO)
            .to(value)
        end
      end
    end

    describe '#loop_back_off_max' do
      subject(:loop_back_off_max) { worker.loop_back_off_max }

      context 'default' do
        it { is_expected.to eq(described_class::BACK_OFF_MAX) }
      end

      context 'when set' do
        let(:value) { rand }

        it do
          expect { worker.send(:loop_back_off_max=, value) }
            .to change { worker.loop_back_off_max }
            .from(described_class::BACK_OFF_MAX)
            .to(value)
        end
      end
    end

    describe '#loop_wait_time' do
      subject(:loop_wait_time) { worker.loop_wait_time }

      context 'default' do
        it { is_expected.to eq(described_class::BASE_INTERVAL) }
      end
    end

    describe '#loop_wait_time=' do
      let(:value) { rand }

      it do
        expect { worker.loop_wait_time = value }
          .to change { worker.loop_wait_time }
          .from(described_class::BASE_INTERVAL)
          .to(value)
      end
    end

    describe '#loop_back_off!' do
      it do
        expect { worker.loop_back_off! }
          .to change { worker.loop_wait_time }
          .from(described_class::BASE_INTERVAL)
          .to(described_class::BASE_INTERVAL * described_class::BACK_OFF_RATIO)

        # Call again to see back-off increase
        expect { worker.loop_back_off! }
          .to change { worker.loop_wait_time }
          .from(described_class::BASE_INTERVAL * described_class::BACK_OFF_RATIO)
          .to(described_class::BASE_INTERVAL * described_class::BACK_OFF_RATIO * described_class::BACK_OFF_RATIO)
      end
    end
  end
end
