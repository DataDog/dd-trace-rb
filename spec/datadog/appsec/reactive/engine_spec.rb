# typed: ignore
# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/engine'

RSpec.describe Datadog::AppSec::Reactive::Engine do
  subject(:engine) { described_class.new }

  context 'subscribe' do
    it 'subscribes block to a list of addresses' do
      expect(engine.subscribers).to be_empty
      engine.subscribe(:a, :b, :c) do
        1 + 1
      end
      expect(engine.subscribers).to_not be_empty
    end

    it 'subscribes multiple times with same addresses appends subscribers' do
      engine.subscribe(:a, :b, :c) do
        1 + 1
      end
      expect(engine.subscribers.size).to eq(1)
      expect(engine.subscribers[[:a, :b, :c]].size).to eq(1)

      engine.subscribe(:a, :b, :c) do
        2 + 2
      end

      expect(engine.subscribers.size).to eq(1)
      expect(engine.subscribers[[:a, :b, :c]].size).to eq(2)
    end
  end

  context 'publish' do
    it 'if no address is subcribed is a no-op' do
      expect do
        engine.publish(:a, 1)
      end.to_not(change { engine.data })
    end

    it 'if address is subcribed it stores the data under the address key' do
      engine.subscribe(:a, :b, :c) do
        1 + 1
      end

      expect do
        engine.publish(:a, 1)
      end.to change { engine.data[:a] }.from(nil).to(1)
    end

    it 'when all addresses are publish it executes subscribed block with published values' do
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

    it 'when multiple subscribers are present only publish for the subscriber that matches all the keys' do
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
