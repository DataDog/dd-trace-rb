# frozen_string_literal: true

require 'datadog/symbol_database/symbol'

RSpec.describe Datadog::SymbolDatabase::Symbol do
  describe '#initialize' do
    it 'creates symbol with required fields' do
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@my_var',
        line: 10,
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
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
        type: 'String',
        language_specifics: {optional: false},
      )

      expect(symbol.symbol_type).to eq('ARG')
      expect(symbol.name).to eq('param1')
      expect(symbol.line).to eq(Datadog::SymbolDatabase::UNKNOWN_MIN_LINE)
      expect(symbol.type).to eq('String')
      expect(symbol.language_specifics).to eq({optional: false})
    end
  end

  describe '#to_h' do
    it 'converts symbol to hash with required fields' do
      symbol = described_class.new(
        symbol_type: 'STATIC_FIELD',
        name: 'CONSTANT',
        line: 5,
      )

      expect(symbol.to_h).to eq({
        symbol_type: 'STATIC_FIELD',
        name: 'CONSTANT',
        line: 5,
      })
    end

    it 'includes optional fields when present' do
      symbol = described_class.new(
        symbol_type: 'LOCAL',
        name: 'local_var',
        line: 15,
        type: 'Integer',
        language_specifics: {inferred: true},
      )

      expect(symbol.to_h).to eq({
        symbol_type: 'LOCAL',
        name: 'local_var',
        line: 15,
        type: 'Integer',
        language_specifics: {inferred: true},
      })
    end

    it 'omits nil values' do
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@var',
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
      )

      expect(symbol.to_h).to eq({
        symbol_type: 'FIELD',
        name: '@var',
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
      })
    end
  end

  describe '#to_json' do
    it 'serializes symbol to JSON' do
      symbol = described_class.new(
        symbol_type: 'ARG',
        name: 'param',
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
        type: 'Hash',
        language_specifics: {required: true},
      )

      expect(JSON.parse(symbol.to_json)).to eq({
        'symbol_type' => 'ARG',
        'name' => 'param',
        'line' => Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
        'type' => 'Hash',
        'language_specifics' => {'required' => true},
      })
    end
  end
end
