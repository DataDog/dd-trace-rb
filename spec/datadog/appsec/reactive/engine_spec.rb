# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/engine'

RSpec.describe Datadog::AppSec::Reactive::Engine do
  subject(:engine) { described_class.new }
  let(:subscribers) { engine.send(:subscribers) }
  let(:data) { engine.send(:data) }

  describe '#subscribe' do
    it 'subscribes block to a list of addresses' do
      expect(subscribers).to be_empty
      engine.subscribe(:a, :b, :c) do
        1 + 1
      end
      expect(subscribers).to_not be_empty
    end

    it 'subscribes multiple times with same addresses appends subscribers' do
      engine.subscribe(:a, :b, :c) do
        1 + 1
      end
      expect(subscribers.size).to eq(1)
      expect(subscribers[[:a, :b, :c]].size).to eq(1)

      engine.subscribe(:a, :b, :c) do
        2 + 2
      end

      expect(subscribers.size).to eq(1)
      expect(subscribers[[:a, :b, :c]].size).to eq(2)
    end
  end

  describe '#publish' do
    context 'when no address is subscribed' do
      it 'is a no-op' do
        expect do
          engine.publish(:a, 1)
        end.to_not(change { data })
      end
    end

    context 'when an address is subscribed' do
      it 'stores the data under the address' do
        engine.subscribe(:a, :b, :c) do
          1 + 1
        end

        expect do
          engine.publish(:a, 1)
        end.to change { data[:a] }.from(nil).to(1)
      end

      it 'executes subscribed block with published values when all addresses are published' do
        expected_values = []
        engine.subscribe(:a, :b, :c) do |*values|
          expected_values = values
          1 + 1
        end

        engine.publish(:a, 1)
        engine.publish(:b, 2)
        engine.publish(:c, 3)

        expect(expected_values).to eq([1, 2, 3])
      end

      context 'when multiple subscribers are present' do
        it 'only publishes for the subscriber that matches all the keys when multiple subscribers are present' do
          expected_values = []
          engine.subscribe(:a, :b, :c) do |*values|
            expected_values = values
            1 + 1
          end

          engine.subscribe(:a, :d, :e) do |*values|
            expected_values = values
            1 + 1
          end

          engine.publish(:a, 1)
          engine.publish(:d, 4)
          engine.publish(:e, 5)
          engine.publish(:b, 2)
          engine.publish(:c, 3)

          expect(expected_values).to eq([1, 2, 3])
        end
      end
    end
  end
end
