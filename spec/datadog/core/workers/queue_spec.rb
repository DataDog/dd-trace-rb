require 'spec_helper'

require 'datadog/core/worker'
require 'datadog/core/workers/queue'

RSpec.describe Datadog::Core::Workers::Queue do
  context 'when included into a worker' do
    subject(:worker) { worker_class.new(&task) }

    let(:worker_class) do
      Class.new(Datadog::Core::Worker) { include Datadog::Core::Workers::Queue }
    end

    let(:task) { proc { |*args| worker_spy.perform(*args) } }
    let(:worker_spy) { double('worker spy') }

    describe '#perform' do
      subject(:perform) { worker.perform }

      context 'when no work is queued' do
        it 'does not perform the task' do
          expect(worker_spy).to_not receive(:perform)
          perform
        end
      end

      context 'when work is queued' do
        let(:args) { [:foo, :bar] }

        before { worker.enqueue(*args) }

        it 'performs the task with arguments provided' do
        end
      end
    end

    describe '#buffer' do
      subject(:buffer) { worker.buffer }

      it { is_expected.to be_a_kind_of(Array) }
      it { is_expected.to be_empty }
    end

    describe '#enqueue' do
      subject(:enqueue) { worker.enqueue(*args) }

      let(:args) { [:foo, :bar] }

      it do
        expect { enqueue }.to change { worker.buffer }
          .from([])
          .to([args])
      end
    end

    describe '#dequeue' do
      subject(:dequeue) { worker.dequeue }

      context 'when nothing is queued' do
        it { is_expected.to be nil }
      end

      context 'when args are queued' do
        let(:args) { [:foo, :bar] }

        before { worker.enqueue(*args) }

        it do
          expect { dequeue }.to change { worker.buffer }
            .from([args])
            .to([])

          is_expected.to eq args
        end
      end
    end

    describe '#work_pending?' do
      subject(:work_pending?) { worker.work_pending? }

      context 'when the buffer is empty' do
        it { is_expected.to be false }
      end

      context 'when the buffer is not empty' do
        before { worker.enqueue(*args) }

        let(:args) { [:foo, :bar] }

        it { is_expected.to be true }
      end
    end
  end
end
