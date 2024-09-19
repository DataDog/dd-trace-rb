require 'spec_helper'

require 'datadog/core/worker'

RSpec.describe Datadog::Core::Worker do
  subject(:worker) { described_class.new(&block) }

  let(:block) { proc {} }

  describe '#initialize' do
    context 'given a block' do
      it { is_expected.to have_attributes(task: block) }
    end
  end

  describe '#perform' do
    subject(:perform) { worker.perform(*args) }

    let(:args) { [:a, :b] }

    context 'when no task has been set' do
      let(:block) { nil }

      it { is_expected.to be nil }
      it { expect { perform }.to_not raise_error }
    end

    context 'when a task has been set' do
      let(:result) { rand }

      before { allow(block).to receive(:call).and_return(result) }

      it 'calls the task and returns its result' do
        is_expected.to be result
        expect(block).to have_received(:call).with(*args)
      end
    end
  end
end
