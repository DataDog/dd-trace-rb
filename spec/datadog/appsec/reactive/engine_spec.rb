# typed: ignore
# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/engine'

RSpec.describe Datadog::AppSec::Reactive::Engine do
  subject { described_class.new }

  context 'subscribe' do
    it 'subscribes block to a list of addresses' do
      expect(subject.subscribers).to be_empty
      subject.subscribe(:a, :b, :c) do
        1 + 1
      end
      expect(subject.subscribers).to_not be_empty
    end

    it 'subscribes multiple times with same addresses appends subscribers' do
      subject.subscribe(:a, :b, :c) do
        1 + 1
      end
      expect(subject.subscribers.size).to eq(1)
      expect(subject.subscribers[[:a, :b, :c]].size).to eq(1)

      subject.subscribe(:a, :b, :c) do
        2 + 2
      end

      expect(subject.subscribers.size).to eq(1)
      expect(subject.subscribers[[:a, :b, :c]].size).to eq(2)
    end
  end

  context 'publish' do
    it 'if no address is subcribed is a no-op' do
      expect {
        subject.publish(:a, 1)
      }.to_not change { subject.data }
    end

    it 'if address is subcribed it stores the data under the address key' do
      subject.subscribe(:a, :b, :c) do
        1 + 1
      end

      expect {
        subject.publish(:a, 1)
      }.to change { subject.data[:a] }.from(nil).to(1)
    end

    it 'when all addresses are publish it executes subscribed block with published values' do
      expected_values = []
      subject.subscribe(:a, :b, :c) do |*values|
        expected_values = values
        1 + 1
      end

      subject.publish(:a, 1)
      subject.publish(:b, 2)
      subject.publish(:c, 3)

      expect(expected_values).to eq([1,2,3])
    end

    it 'when multiple subscribers are present only publish for the subscriber that matches all the keys' do
      expected_values = []
      subject.subscribe(:a, :b, :c) do |*values|
        expected_values = values
        1 + 1
      end

      subject.subscribe(:a, :d, :e) do |*values|
        expected_values = values
        1 + 1
      end

      subject.publish(:a, 1)
      subject.publish(:d, 4)
      subject.publish(:e, 5)
      subject.publish(:b, 2)
      subject.publish(:c, 3)

      expect(expected_values).to eq([1,2,3])
    end
  end
end
