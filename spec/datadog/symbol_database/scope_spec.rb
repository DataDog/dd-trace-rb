# frozen_string_literal: true

require 'datadog/symbol_database/scope'
require 'datadog/symbol_database/symbol_entry'

RSpec.describe Datadog::SymbolDatabase::Scope do
  describe '#to_h' do
    it 'includes scope_type and defaults start_line/end_line to 0' do
      scope = described_class.new(scope_type: 'MODULE', name: 'test')
      h = scope.to_h
      expect(h[:scope_type]).to eq('MODULE')
      expect(h[:name]).to eq('test')
      expect(h[:start_line]).to eq(0)
      expect(h[:end_line]).to eq(0)
      expect(h).not_to have_key(:source_file)
      expect(h).not_to have_key(:symbols)
      expect(h).not_to have_key(:scopes)
    end

    it 'includes all fields when set' do
      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
        source_file: '/app/my_class.rb',
        start_line: 5,
        end_line: 50,
        language_specifics: { access_modifiers: ['public'] },
        symbols: [Datadog::SymbolDatabase::SymbolEntry.new(symbol_type: 'FIELD', name: '@foo', line: 0)],
        scopes: [described_class.new(scope_type: 'METHOD', name: 'bar')],
      )
      h = scope.to_h
      expect(h[:scope_type]).to eq('CLASS')
      expect(h[:name]).to eq('MyClass')
      expect(h[:source_file]).to eq('/app/my_class.rb')
      expect(h[:start_line]).to eq(5)
      expect(h[:end_line]).to eq(50)
      expect(h[:language_specifics]).to eq({ access_modifiers: ['public'] })
      expect(h[:symbols]).to be_an(Array)
      expect(h[:symbols].first[:name]).to eq('@foo')
      expect(h[:scopes]).to be_an(Array)
      expect(h[:scopes].first[:scope_type]).to eq('METHOD')
    end

    it 'omits empty language_specifics' do
      scope = described_class.new(scope_type: 'LOCAL', language_specifics: {})
      expect(scope.to_h).not_to have_key(:language_specifics)
    end

    it 'omits empty symbols array' do
      scope = described_class.new(scope_type: 'METHOD', symbols: [])
      expect(scope.to_h).not_to have_key(:symbols)
    end
  end
end
