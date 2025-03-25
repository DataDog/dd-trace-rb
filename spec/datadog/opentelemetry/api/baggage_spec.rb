# frozen_string_literal: true

require 'spec_helper'
require 'opentelemetry/sdk'
require 'datadog/opentelemetry'

RSpec.describe Datadog::OpenTelemetry::API::Baggage do
  subject(:baggage) { ::OpenTelemetry::Baggage }

  let(:trace) { Datadog::Tracing::TraceOperation.new }
  let(:context) { ::OpenTelemetry::Context.current }

  describe '#set_value' do
    it 'sets a baggage value in the trace' do
      ctx = baggage.set_value('test_key', 'test_value')
      expect(ctx).to be_a(OpenTelemetry::Context)
      expect(ctx.instance_variable_get(:@trace).baggage['test_key']).to eq('test_value')
    end

    it 'updates an existing baggage value' do
      ctx = baggage.set_value('test_key', 'initial_value')
      ctx = baggage.set_value('test_key', 'new_value', context: ctx)

      expect(ctx).to be_a(OpenTelemetry::Context)
      expect(ctx.instance_variable_get(:@trace).baggage['test_key']).to eq('new_value')
    end

    it 'preserves existing baggage values when adding new ones' do
      ctx = baggage.set_value('key1', 'value1')
      ctx = baggage.set_value('key2', 'value2', context: ctx)

      expect(ctx.instance_variable_get(:@trace).baggage).to eq(
        {
          'key1' => 'value1',
          'key2' => 'value2'
        }
      )
    end

    it 'maintains immutability of the baggage hash' do
      baggage.set_value('test_key', 'test_value')

      expect(baggage.values).to eq({})
    end
  end

  describe '#remove_value' do
    let(:ctx) do
      ctx1 = baggage.set_value('key1', 'value1')
      baggage.set_value('key2', 'value2', context: ctx1)
    end

    it 'removes a baggage value from the trace' do
      result = baggage.remove_value('key1', context: ctx)

      expect(result).to be_a(OpenTelemetry::Context)
      expect(result.instance_variable_get(:@trace).baggage).to eq({ 'key2' => 'value2' })
    end

    it 'preserves other baggage values when removing one' do
      result = baggage.remove_value('key1', context: ctx)

      expect(result.instance_variable_get(:@trace).baggage).to eq({ 'key2' => 'value2' })
    end

    it 'handles removing non-existent keys' do
      result = baggage.remove_value('non_existent_key', context: ctx)

      expect(result).to be_a(OpenTelemetry::Context)
      expect(result.instance_variable_get(:@trace).baggage).to eq(
        {
          'key1' => 'value1',
          'key2' => 'value2'
        }
      )
    end
  end

  describe '#value' do
    let(:ctx) do
      baggage.set_value('key1', 'value1')
    end

    it 'retrieves a baggage value from the trace' do
      expect(baggage.value('key1', context: ctx)).to eq('value1')
    end

    it 'returns nil for non-existent keys' do
      expect(baggage.value('non_existent_key', context: ctx)).to be_nil
    end
  end

  describe '#values' do
    let(:ctx) do
      ctx1 = baggage.set_value('key1', 'value1')
      baggage.set_value('key2', 'value2', context: ctx1)
    end

    it 'returns all baggage values from the trace' do
      expect(baggage.values(context: ctx)).to eq(
        {
          'key1' => 'value1',
          'key2' => 'value2'
        }
      )
    end

    it 'returns a new context with the updated baggage' do
      values = baggage.values(context: ctx)
      values['key3'] = 'value3'

      expect(baggage.values(context: ctx)).not_to include('key3')
      expect(ctx.instance_variable_get(:@trace).baggage).not_to include('key3')
    end
  end

  describe '#clear' do
    let(:ctx) do
      ctx1 = baggage.set_value('key1', 'value1')
      baggage.set_value('key2', 'value2', context: ctx1)
    end

    it 'removes all baggage values from the trace' do
      result = baggage.clear(context: ctx)

      expect(result).to be_a(OpenTelemetry::Context)
      expect(result.instance_variable_get(:@trace).baggage).to be_empty
    end

    it 'maintains immutability when clearing' do
      original_baggage = ctx.instance_variable_get(:@trace).baggage.dup
      result = baggage.clear(context: ctx)

      expect(result.instance_variable_get(:@trace).baggage).not_to be(original_baggage)
    end
  end
end
