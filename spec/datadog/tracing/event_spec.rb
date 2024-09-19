require 'spec_helper'

require 'datadog/core'
require 'datadog/tracing/event'

RSpec.describe Datadog::Tracing::Event do
  subject(:event) { described_class.new(name) }

  let(:name) { :test_event }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        name: name,
        subscriptions: kind_of(Array)
      )
    end
  end

  describe '#subscribe' do
    subject(:subscribe) { event.subscribe(&block) }

    context 'when given a block' do
      let(:block) { proc {} }

      it 'adds a new subscription' do
        expect { subscribe }.to change { event.subscriptions }
          .from([])
          .to([block])
      end
    end

    context 'when not given a block' do
      let(:block) { nil }

      it { expect { subscribe }.to raise_error(ArgumentError) }
    end
  end

  describe '#unsubscribe_all!' do
    subject(:unsubscribe_all!) { event.unsubscribe_all! }

    context 'after multiple subscriptions have been made' do
      before { 2.times { event.subscribe(&proc {}) } }

      it 'removes all the subscriptions' do
        expect { unsubscribe_all! }.to change { event.subscriptions.empty? }
          .from(false)
          .to(true)

        is_expected.to be true
      end
    end
  end

  describe '#publish' do
    subject(:publish) { event.publish(*args) }

    let(:args) { [:a, :b] }

    context 'when there are no subscribers' do
      it { expect { publish }.to_not raise_error }
      it { is_expected.to be true }
    end

    context 'when there are multiple subscribers' do
      let(:subscriptions) do
        [
          proc { |*_args| },
          proc { |*_args| }
        ]
      end

      before do
        subscriptions.each do |block|
          allow(block).to receive(:call)
          event.subscribe(&block)
        end
      end

      it 'calls both subscribers' do
        publish

        expect(subscriptions).to all(have_received(:call).with(*args).ordered)
      end

      context 'and the first raises an error' do
        let(:error) { StandardError.new('Failure!') }

        before do
          allow(subscriptions[0]).to receive(:call).and_raise(error)
          allow(Datadog.logger).to receive(:debug)
        end

        it 'logs an error and continues to the next' do
          publish

          expect(Datadog.logger).to have_lazy_debug_logged(/Error while handling '#{name}'/)
          expect(subscriptions[1]).to have_received(:call).with(*args)
        end
      end
    end
  end
end
