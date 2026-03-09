# frozen_string_literal: true

require 'datadog/symbol_database/symbol'

RSpec.describe Datadog::SymbolDatabase::Symbol do
  describe '#initialize' do
    it 'creates symbol with required fields' do
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@my_var',
        line: 10
      )

      expect(symbol.symbol_type).to eq('FIELD')
      expect(symbol.name).to eq('@my_var')
      expect(symbol.line).to eq(10)
      expect(symbol.type).to be_nil
      expect(symbol.language_specifics).to be_nil
    end

    it 'creates symbol with all fields' do
      symbol = described_class.new(
        symbol_type: 'ARG',
        name: 'param1',
        line: 0,
        type: 'String',
        language_specifics: {optional: false}
      )

      expect(symbol.symbol_type).to eq('ARG')
      expect(symbol.name).to eq('param1')
      expect(symbol.line).to eq(0)
      expect(symbol.type).to eq('String')
      expect(symbol.language_specifics).to eq({optional: false})
    end
  end

  describe '#to_h' do
    it 'converts symbol to hash with required fields' do
      symbol = described_class.new(
        symbol_type: 'STATIC_FIELD',
        name: 'CONSTANT',
        line: 5
      )

      hash = symbol.to_h

      expect(hash).to eq({
        symbol_type: 'STATIC_FIELD',
        name: 'CONSTANT',
        line: 5
      })
    end

    it 'includes optional type field when present' do
      symbol = described_class.new(
        symbol_type: 'LOCAL',
        name: 'local_var',
        line: 15,
        type: 'Integer'
      )

      hash = symbol.to_h

      expect(hash).to include(
        symbol_type: 'LOCAL',
        name: 'local_var',
        line: 15,
        type: 'Integer'
      )
    end

    it 'removes nil values via compact' do
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@var',
        line: 0,
        type: nil,
        language_specifics: nil
      )

      hash = symbol.to_h

      expect(hash).to eq({
        symbol_type: 'FIELD',
        name: '@var',
        line: 0
      })
      expect(hash).not_to have_key(:type)
      expect(hash).not_to have_key(:language_specifics)
    end

    it 'handles line number 0 (available in entire scope)' do
      symbol = described_class.new(
        symbol_type: 'ARG',
        name: 'param',
        line: 0
      )

      hash = symbol.to_h

      expect(hash[:line]).to eq(0)
    end

    it 'handles line number 2147483647 (INT_MAX)' do
      symbol = described_class.new(
        symbol_type: 'LOCAL',
        name: 'var',
        line: 2147483647
      )

      hash = symbol.to_h

      expect(hash[:line]).to eq(2147483647)
    end
  end

  describe '#to_json' do
    it 'serializes symbol to JSON string' do
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@my_field',
        line: 10
      )

      json = symbol.to_json

      expect(json).to be_a(String)
      parsed = JSON.parse(json)
      expect(parsed['symbol_type']).to eq('FIELD')
      expect(parsed['name']).to eq('@my_field')
      expect(parsed['line']).to eq(10)
    end

    it 'produces valid JSON for symbol with all fields' do
      symbol = described_class.new(
        symbol_type: 'ARG',
        name: 'param',
        line: 0,
        type: 'Hash',
        language_specifics: {required: true}
      )

      json = symbol.to_json
      parsed = JSON.parse(json)

      expect(parsed).to include(
        'symbol_type' => 'ARG',
        'name' => 'param',
        'line' => 0,
        'type' => 'Hash',
        'language_specifics' => {'required' => true}
      )
    end
  end
end
