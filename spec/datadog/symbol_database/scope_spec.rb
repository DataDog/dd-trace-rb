# frozen_string_literal: true

require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::Scope do
  describe '#initialize' do
    it 'creates scope with required fields' do
      scope = described_class.new(scope_type: 'CLASS')

      expect(scope.scope_type).to eq('CLASS')
      expect(scope.name).to be_nil
      expect(scope.language_specifics).to eq({})
      expect(scope.symbols).to eq([])
      expect(scope.scopes).to eq([])
    end
  end

  describe '#to_h' do
    it 'serializes nested symbols and scopes' do
      symbol = Datadog::SymbolDatabase::Symbol.new(
        symbol_type: 'FIELD',
        name: '@field',
        line: 5,
      )
      method_scope = described_class.new(
        scope_type: 'METHOD',
        name: 'call',
        start_line: 10,
        end_line: 12,
        has_injectible_lines: true,
        injectible_lines: [{start: 10, end: 12}],
      )
      class_scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
        source_file: '/app/my_class.rb',
        start_line: 1,
        end_line: 20,
        language_specifics: {super_classes: ['Base']},
        symbols: [symbol],
        scopes: [method_scope],
      )

      expect(class_scope.to_h).to eq({
        scope_type: 'CLASS',
        name: 'MyClass',
        source_file: '/app/my_class.rb',
        start_line: 1,
        end_line: 20,
        language_specifics: {super_classes: ['Base']},
        symbols: [
          {
            symbol_type: 'FIELD',
            name: '@field',
            line: 5,
          },
        ],
        scopes: [
          {
            scope_type: 'METHOD',
            name: 'call',
            start_line: 10,
            end_line: 12,
            has_injectible_lines: true,
            injectible_lines: [{start: 10, end: 12}],
          },
        ],
      })
    end

    it 'omits empty collections and nil fields' do
      scope = described_class.new(
        scope_type: 'MODULE',
        name: 'MyModule',
      )

      expect(scope.to_h).to eq({
        scope_type: 'MODULE',
        name: 'MyModule',
      })
    end

    it 'emits method injectable line state even when false' do
      scope = described_class.new(
        scope_type: 'METHOD',
        name: 'native_call',
        has_injectible_lines: false,
      )

      expect(scope.to_h).to eq({
        scope_type: 'METHOD',
        name: 'native_call',
        has_injectible_lines: false,
      })
    end

    it 'does not emit injectable line fields for non-method scopes' do
      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
        has_injectible_lines: true,
        injectible_lines: [{start: 1, end: 2}],
      )

      expect(scope.to_h).to eq({
        scope_type: 'CLASS',
        name: 'MyClass',
      })
    end
  end

  describe '#to_json' do
    it 'serializes scope to JSON' do
      scope = described_class.new(
        scope_type: 'METHOD',
        name: 'perform',
        start_line: 7,
        end_line: 9,
        has_injectible_lines: false,
      )

      expect(JSON.parse(scope.to_json)).to eq({
        'scope_type' => 'METHOD',
        'name' => 'perform',
        'start_line' => 7,
        'end_line' => 9,
        'has_injectible_lines' => false,
      })
    end
  end
end
