# frozen_string_literal: true

# DESIGN VERIFICATION SUMMARY FOR SYMBOL TESTS:
#
# Tests verify behavior from:
#   - specs/json-schema.md (Symbol Object, SymbolType enum, Special Line Values)
#   - design/symbol-extraction.md (data model, parameter extraction)
#   - design/json-serialization.md (compact serialization)
#
# Test accuracy:
#   - FIELD symbol tests: ACCURATE for data model. Note: Ruby does not currently
#     emit FIELD symbols (instance var extraction deferred per requirements.md).
#   - STATIC_FIELD tests: ACCURATE per specs/json-schema.md line 167.
#   - ARG tests: ACCURATE per specs/json-schema.md line 168.
#   - LOCAL tests: ACCURATE for data model (deferred feature per design).
#   - UNKNOWN_MIN_LINE/UNKNOWN_MAX_LINE tests: ACCURATE per specs/json-schema.md
#     "Special Line Number Values" table.
#   - .compact behavior tests: ACCURATE per specs/json-schema.md Optional Fields Policy.

require 'datadog/symbol_database'
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
      # DESIGN VERIFICATION: ARG with UNKNOWN_MIN_LINE (0) means parameter is
      #   available throughout entire method scope.
      #   Source: specs/json-schema.md "Special Line Number Values" -- ACCURATE

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
      # DESIGN VERIFICATION: STATIC_FIELD for constant.
      #   Source: specs/json-schema.md line 167 -- ACCURATE

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
        type: 'Integer',
      )
      # DESIGN VERIFICATION: LOCAL symbol with type annotation.
      #   Source: specs/json-schema.md line 159, 169
      #   LOCAL extraction is deferred for Ruby but data model supports it. ACCURATE.

      hash = symbol.to_h

      expect(hash).to include(
        symbol_type: 'LOCAL',
        name: 'local_var',
        line: 15,
        type: 'Integer',
      )
    end

    it 'removes nil values via compact' do
      # DESIGN VERIFICATION: specs/json-schema.md "Optional Fields Policy" -- ACCURATE
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@var',
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
        type: nil,
        language_specifics: nil,
      )

      hash = symbol.to_h

      expect(hash).to eq({
        symbol_type: 'FIELD',
        name: '@var',
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE
      })
      expect(hash).not_to have_key(:type)
      expect(hash).not_to have_key(:language_specifics)
    end

    it 'handles UNKNOWN_MIN_LINE (available in entire scope)' do
      # DESIGN VERIFICATION: specs/json-schema.md "Special Line Number Values"
      #   "0 = Start of scope, Symbol available from start of scope" -- ACCURATE
      symbol = described_class.new(
        symbol_type: 'ARG',
        name: 'param',
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
      )

      hash = symbol.to_h

      expect(hash[:line]).to eq(Datadog::SymbolDatabase::UNKNOWN_MIN_LINE)
    end

    it 'handles UNKNOWN_MAX_LINE (method-level only)' do
      # DESIGN VERIFICATION: specs/json-schema.md "Special Line Number Values"
      #   "2147483647 = End of scope (INT_MAX), avoid line probe completion" -- ACCURATE
      symbol = described_class.new(
        symbol_type: 'LOCAL',
        name: 'var',
        line: Datadog::SymbolDatabase::UNKNOWN_MAX_LINE,
      )

      hash = symbol.to_h

      expect(hash[:line]).to eq(Datadog::SymbolDatabase::UNKNOWN_MAX_LINE)
    end
  end

  describe '#to_json' do
    it 'serializes symbol to JSON string' do
      symbol = described_class.new(
        symbol_type: 'FIELD',
        name: '@my_field',
        line: 10,
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
        line: Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
        type: 'Hash',
        language_specifics: {required: true},
      )

      json = symbol.to_json
      parsed = JSON.parse(json)

      expect(parsed).to include(
        'symbol_type' => 'ARG',
        'name' => 'param',
        'line' => Datadog::SymbolDatabase::UNKNOWN_MIN_LINE,
        'type' => 'Hash',
        'language_specifics' => {'required' => true},
      )
    end
  end
end
