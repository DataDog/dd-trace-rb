# frozen_string_literal: true

require 'spec_helper'
require 'datadog/opentelemetry'

RSpec.describe Datadog::OpenTelemetry::API::Baggage do
  subject(:baggage) { described_class.new }

  # Mock Context class for testing
  let(:context) do
    Class.new do
      attr_accessor :trace

      def initialize(trace = nil)
        @trace = trace
      end

      def ensure_trace
        @trace ||= Datadog::Tracing::TraceOperation.new(
          id: Datadog::Tracing::Utils.next_id,
          parent_id: Datadog::Tracing::Utils.next_id,
          sampled: true
        )
      end
    end.new
  end

  describe '#value' do
    context 'when baggage is empty' do
      it 'returns nil for any key' do
        expect(baggage.value('test_key', context: context)).to be_nil
      end
    end

    context 'when baggage has values' do
      before do
        context.ensure_trace.baggage = { 'test_key' => 'test_value', 'another_key' => 'another_value' }
      end

      it 'returns the value for an existing key' do
        expect(baggage.value('test_key', context: context)).to eq('test_value')
      end

      it 'returns nil for a non-existent key' do
        expect(baggage.value('non_existent_key', context: context)).to be_nil
      end
    end
  end

  describe '#values' do
    context 'when baggage is empty' do
      it 'returns an empty hash' do
        expect(baggage.values(context: context)).to eq({})
      end
    end

    context 'when baggage has values' do
      let(:baggage_data) { { 'test_key' => 'test_value', 'another_key' => 'another_value' } }

      before do
        context.ensure_trace.baggage = baggage_data
      end

      it 'returns all baggage values' do
        expect(baggage.values(context: context)).to eq(baggage_data)
      end

      it 'returns a copy of the baggage' do
        result = baggage.values(context: context)
        result['new_key'] = 'new_value'

        # Original baggage should remain unchanged
        expect(context.trace.baggage).to eq(baggage_data)
      end
    end
  end

  describe '#set_value' do
    context 'when baggage is empty' do
      it 'initializes baggage and sets the value' do
        baggage.set_value('test_key', 'test_value', context: context)

        expect(context.trace.baggage).to eq({ 'test_key' => 'test_value' })
      end
    end

    context 'when baggage already has values' do
      before do
        context.ensure_trace.baggage = { 'existing_key' => 'existing_value' }
      end

      it 'adds a new key-value pair' do
        baggage.set_value('test_key', 'test_value', context: context)

        expect(context.trace.baggage).to eq(
          {
            'existing_key' => 'existing_value',
            'test_key' => 'test_value'
          }
        )
      end

      it 'updates an existing key' do
        baggage.set_value('existing_key', 'new_value', context: context)

        expect(context.trace.baggage).to eq({ 'existing_key' => 'new_value' })
      end

      it 'maintains immutability by creating a copy' do
        original_baggage = context.trace.baggage
        baggage.set_value('test_key', 'test_value', context: context)

        # The original hash object should not be the same as the new one
        expect(context.trace.baggage).not_to be(original_baggage)
      end
    end

    it 'returns the context' do
      result = baggage.set_value('test_key', 'test_value', context: context)

      expect(result).to be(context)
    end
  end

  describe '#remove_value' do
    context 'when baggage is empty' do
      it 'returns the context unchanged' do
        result = baggage.remove_value('test_key', context: context)

        expect(result).to be(context)
        expect(context.trace.baggage).to be_nil
      end
    end

    context 'when baggage has values' do
      before do
        context.ensure_trace.baggage = { 'test_key' => 'test_value', 'another_key' => 'another_value' }
      end

      it 'removes an existing key' do
        baggage.remove_value('test_key', context: context)

        expect(context.trace.baggage).to eq({ 'another_key' => 'another_value' })
      end

      it 'returns the context unchanged when key does not exist' do
        original_baggage = context.trace.baggage.dup
        baggage.remove_value('non_existent_key', context: context)

        expect(context.trace.baggage).to eq(original_baggage)
      end

      it 'maintains immutability by creating a copy' do
        original_baggage = context.trace.baggage
        baggage.remove_value('test_key', context: context)

        # The original hash object should not be the same as the new one
        expect(context.trace.baggage).not_to be(original_baggage)
      end
    end

    it 'returns the context' do
      context.ensure_trace.baggage = { 'test_key' => 'test_value' }
      result = baggage.remove_value('test_key', context: context)

      expect(result).to be(context)
    end
  end

  describe '#clear' do
    context 'when baggage has values' do
      before do
        context.ensure_trace.baggage = { 'test_key' => 'test_value', 'another_key' => 'another_value' }
      end

      it 'clears all baggage values' do
        # Mock the clear method since we're not testing its implementation
        expect(context.ensure_trace.baggage).to receive(:clear)

        baggage.clear(context: context)
      end
    end
  end
end
