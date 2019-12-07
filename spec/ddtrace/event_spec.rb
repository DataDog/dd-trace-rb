require 'spec_helper'

require 'ddtrace'
require 'ddtrace/event'

RSpec.describe Datadog::Event do
  subject(:event) { described_class.new(name) }
  let(:name) { :test_event }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        name: name,
        subscriptions: kind_of(Hash)
      )
    end
  end

  describe '#subscribe' do
    subject(:subscribe) { event.subscribe(key, &block) }
    let(:key) { :test_subscription }

    context 'when given a key and block' do
      let(:block) { proc {} }

      it 'adds a new subscription' do
        expect { subscribe }.to change { event.subscriptions[key] }
          .from(nil)
          .to(block)
      end

      context 'whose key already exists' do
        let(:old_block) { proc {} }
        before { event.subscribe(key, &old_block) }

        it 'replaces the original subscription' do
          expect { subscribe }.to change { event.subscriptions[key] }
            .from(old_block)
            .to(block)
        end
      end
    end

    context 'when not given a block' do
      let(:block) { nil }
      it { expect { subscribe }.to raise_error(ArgumentError) }
    end
  end

  describe '#unsubscribe' do
    subject(:unsubscribe) { event.unsubscribe(key) }
    let(:key) { :test_subscription }

    context 'when no subscription has been made' do
      it { is_expected.to be nil }
    end

    context 'after a subscription has been made' do
      let(:block) { proc {} }
      before { event.subscribe(key, &block) }

      it 'removes the subscription' do
        expect { unsubscribe }.to change { event.subscriptions[key] }
          .from(block)
          .to(nil)

        is_expected.to be block
      end
    end
  end

  describe '#unsubscribe_all!' do
    subject(:unsubscribe_all!) { event.unsubscribe_all! }

    context 'after multiple subscriptions have been made' do
      before { 2.times { |i| event.subscribe(i, &proc {}) } }

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
        {
          first: proc { |*_args| },
          second: proc { |*_args| }
        }
      end

      before do
        subscriptions.each do |key, block|
          allow(block).to receive(:call)
          event.subscribe(key, &block)
        end
      end

      it 'calls both subscribers' do
        publish

        subscriptions.values.each do |block|
          expect(block).to have_received(:call).with(*args).ordered
        end
      end

      context 'and the first raises an error' do
        let(:error) { StandardError.new('Failure!') }

        before do
          allow(subscriptions[:first]).to receive(:call).and_raise(error)
          allow(Datadog::Logger.log).to receive(:debug)
        end

        it 'logs an error and continues to the next' do
          publish

          expect(Datadog::Logger.log).to have_received(:debug).with(/Error while handling 'first'/).once
          expect(subscriptions[:second]).to have_received(:call).with(*args)
        end
      end
    end
  end
end
