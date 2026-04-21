# frozen_string_literal: true

# DESIGN VERIFICATION SUMMARY FOR SCOPE TESTS:
#
# Tests verify behavior from:
#   - specs/json-schema.md (Scope Object, Optional Fields Policy, Special Line Values)
#   - design/json-serialization.md (compact serialization, empty field handling)
#   - design/symbol-extraction.md (Injectable Lines, data model defaults)
#
# Test accuracy:
#   - All #initialize tests: ACCURATE -- match design/symbol-extraction.md defaults
#   - All #to_h compact/nil tests: ACCURATE -- match specs/json-schema.md Optional Fields Policy
#   - All injectable lines tests: ACCURATE -- match specs/json-schema.md line 74-75
#   - Nested hierarchy test: ACCURATE but INCOMPLETE -- tests MODULE->CLASS->METHOD
#     but does not test FILE->MODULE/CLASS->METHOD (the actual Ruby hierarchy per
#     design/scope-hierarchy.md). No test creates a FILE scope as root of a hierarchy.
#   - "complete payload" test in service_version_spec uses MODULE as root scope type
#     (line 146: scope_type: 'MODULE') -- per specs/json-schema.md line 126, Ruby
#     root scopes should be FILE, not MODULE. Test is valid for the data model
#     (MODULE is an allowed scope_type) but does not exercise the actual Ruby protocol.

require 'datadog/symbol_database/scope'
require 'datadog/symbol_database/symbol'

RSpec.describe Datadog::SymbolDatabase::Scope do
  describe '#initialize' do
    it 'creates scope with required fields' do
      scope = described_class.new(scope_type: 'CLASS')

      expect(scope.scope_type).to eq('CLASS')
      expect(scope.name).to be_nil
      expect(scope.symbols).to eq([])
      expect(scope.scopes).to eq([])
    end

    it 'creates scope with all fields' do
      scope = described_class.new(
        scope_type: 'METHOD',
        name: 'my_method',
        source_file: '/path/to/file.rb',
        start_line: 10,
        end_line: 20,
        language_specifics: {visibility: 'public'},
        symbols: [],
        scopes: [],
      )
      # DESIGN VERIFICATION: METHOD language_specifics {visibility: 'public'}
      #   Source: specs/json-schema.md lines 249-255 -- ACCURATE

      expect(scope.scope_type).to eq('METHOD')
      expect(scope.name).to eq('my_method')
      expect(scope.source_file).to eq('/path/to/file.rb')
      expect(scope.start_line).to eq(10)
      expect(scope.end_line).to eq(20)
      expect(scope.language_specifics).to eq({visibility: 'public'})
    end

    it 'defaults language_specifics to empty hash' do
      # DESIGN VERIFICATION: design/symbol-extraction.md line ~505 -- ACCURATE
      scope = described_class.new(scope_type: 'CLASS')
      expect(scope.language_specifics).to eq({})
    end

    it 'defaults symbols to empty array' do
      scope = described_class.new(scope_type: 'CLASS')
      expect(scope.symbols).to eq([])
    end

    it 'defaults scopes to empty array' do
      scope = described_class.new(scope_type: 'CLASS')
      expect(scope.scopes).to eq([])
    end
  end

  describe '#to_h' do
    it 'converts simple scope to hash' do
      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
      )

      hash = scope.to_h

      expect(hash).to eq({
        scope_type: 'CLASS',
        name: 'MyClass'
      })
    end

    it 'includes all non-nil fields' do
      scope = described_class.new(
        scope_type: 'METHOD',
        name: 'my_method',
        source_file: '/path/file.rb',
        start_line: 10,
        end_line: 20
      )
      # DESIGN VERIFICATION: METHOD with start_line != end_line.
      #   Per design/symbol-extraction.md line ~183, METHOD end_line originally
      #   equals start_line (Ruby doesn't provide end line), but injectable lines
      #   now fix this. Test uses distinct values which is valid. ACCURATE.

      hash = scope.to_h

      expect(hash).to include(
        scope_type: 'METHOD',
        name: 'my_method',
        source_file: '/path/file.rb',
        start_line: 10,
        end_line: 20
      )
    end

    it 'removes nil values via compact' do
      # DESIGN VERIFICATION: specs/json-schema.md "Optional Fields Policy" -- ACCURATE
      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
        source_file: nil,
        start_line: nil,
      )

      hash = scope.to_h

      expect(hash).to eq({
        scope_type: 'CLASS',
        name: 'MyClass'
      })
      expect(hash).not_to have_key(:source_file)
      expect(hash).not_to have_key(:start_line)
    end

    it 'excludes empty language_specifics' do
      # DESIGN VERIFICATION: design/json-serialization.md line 59 -- ACCURATE
      scope = described_class.new(
        scope_type: 'CLASS',
        language_specifics: {},
      )

      hash = scope.to_h

      expect(hash).not_to have_key(:language_specifics)
    end

    it 'includes non-empty language_specifics' do
      # DESIGN VERIFICATION: specs/json-schema.md CLASS language_specifics
      #   super_classes field -- ACCURATE
      scope = described_class.new(
        scope_type: 'CLASS',
        language_specifics: {super_classes: ['BaseClass']},
      )

      hash = scope.to_h

      expect(hash).to include(language_specifics: {super_classes: ['BaseClass']})
    end

    it 'excludes empty symbols array' do
      # DESIGN VERIFICATION: specs/json-schema.md "Don't include empty arrays" -- ACCURATE
      scope = described_class.new(
        scope_type: 'CLASS',
        symbols: [],
      )

      hash = scope.to_h

      expect(hash).not_to have_key(:symbols)
    end

    it 'includes non-empty symbols array' do
      symbol = Datadog::SymbolDatabase::Symbol.new(
        symbol_type: 'FIELD',
        name: 'my_field',
        line: 5,
      )
      # DESIGN VERIFICATION: FIELD symbol with specific line number.
      #   Per requirements.md, FIELD extraction is deferred for Ruby, but the
      #   data model accepts it. Test is valid for the model. ACCURATE.

      scope = described_class.new(
        scope_type: 'CLASS',
        symbols: [symbol],
      )

      hash = scope.to_h

      expect(hash[:symbols]).to be_an(Array)
      expect(hash[:symbols].size).to eq(1)
      expect(hash[:symbols].first).to include(
        symbol_type: 'FIELD',
        name: 'my_field',
        line: 5,
      )
    end

    it 'excludes empty nested scopes array' do
      scope = described_class.new(
        scope_type: 'MODULE',
        scopes: [],
      )

      hash = scope.to_h

      expect(hash).not_to have_key(:scopes)
    end

    it 'includes non-empty nested scopes array' do
      nested_scope = described_class.new(
        scope_type: 'CLASS',
        name: 'NestedClass',
      )

      scope = described_class.new(
        scope_type: 'MODULE',
        scopes: [nested_scope],
      )

      hash = scope.to_h

      expect(hash[:scopes]).to be_an(Array)
      expect(hash[:scopes].size).to eq(1)
      expect(hash[:scopes].first).to include(
        scope_type: 'CLASS',
        name: 'NestedClass',
      )
    end

    it 'handles FILE-rooted Ruby scope hierarchy' do
      # Mirrors specs/json-schema.md Scenario 3: FILE -> MODULE -> CLASS -> METHOD
      method_scope = described_class.new(
        scope_type: 'METHOD',
        name: 'subscribed',
        start_line: 3,
        end_line: 5,
      )

      class_scope = described_class.new(
        scope_type: 'CLASS',
        name: 'ApplicationCable::Channel',
        scopes: [method_scope],
      )

      module_scope = described_class.new(
        scope_type: 'MODULE',
        name: 'ApplicationCable',
        scopes: [class_scope],
      )

      file_scope = described_class.new(
        scope_type: 'FILE',
        name: '/app/channels/application_cable/channel.rb',
        source_file: '/app/channels/application_cable/channel.rb',
        start_line: 0,
        end_line: 2147483647,
        language_specifics: {file_hash: 'abc123'},
        scopes: [module_scope],
      )

      hash = file_scope.to_h

      expect(hash[:scope_type]).to eq('FILE')
      expect(hash[:language_specifics]).to eq({file_hash: 'abc123'})
      expect(hash[:scopes].first[:scope_type]).to eq('MODULE')
      expect(hash[:scopes].first[:scopes].first[:scope_type]).to eq('CLASS')
      expect(hash[:scopes].first[:scopes].first[:scopes].first[:scope_type]).to eq('METHOD')
    end

    it 'includes injectable lines fields on METHOD scope with ranges' do
      # DESIGN VERIFICATION: specs/json-schema.md line 74-75
      #   has_injectible_lines: true + injectible_lines present on METHOD -- ACCURATE
      scope = described_class.new(
        scope_type: 'METHOD',
        name: 'my_method',
        has_injectible_lines: true,
        injectible_lines: [{start: 10, end: 12}, {start: 15, end: 15}],
      )

      hash = scope.to_h

      expect(hash[:has_injectible_lines]).to eq(true)
      expect(hash[:injectible_lines]).to eq([{start: 10, end: 12}, {start: 15, end: 15}])
    end

    it 'includes has_injectible_lines: false on METHOD scope without ranges' do
      # DESIGN VERIFICATION: design/symbol-extraction.md "Injectable Lines" > "Serialization"
      #   "Always emit has_injectible_lines on METHOD scopes" -- ACCURATE
      #   "Emit injectible_lines only when non-empty" -- ACCURATE
      scope = described_class.new(
        scope_type: 'METHOD',
        name: 'native_method',
        has_injectible_lines: false,
        injectible_lines: nil,
      )

      hash = scope.to_h

      expect(hash[:has_injectible_lines]).to eq(false)
      expect(hash).not_to have_key(:injectible_lines)
    end

    it 'excludes injectable lines fields from CLASS scope' do
      # DESIGN VERIFICATION: specs/json-schema.md line 74
      #   "Not present on CLASS, FILE, MODULE scopes" -- ACCURATE
      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
      )

      hash = scope.to_h

      expect(hash).not_to have_key(:has_injectible_lines)
      expect(hash).not_to have_key(:injectible_lines)
    end

    it 'excludes injectable lines fields from MODULE scope' do
      # DESIGN VERIFICATION: specs/json-schema.md line 74 -- ACCURATE
      scope = described_class.new(
        scope_type: 'MODULE',
        name: 'MyModule',
      )

      hash = scope.to_h

      expect(hash).not_to have_key(:has_injectible_lines)
      expect(hash).not_to have_key(:injectible_lines)
    end

    it 'excludes injectable lines fields from FILE scope' do
      # DESIGN VERIFICATION: specs/json-schema.md line 74 -- ACCURATE
      scope = described_class.new(
        scope_type: 'FILE',
        name: '/app/test.rb',
      )

      hash = scope.to_h

      expect(hash).not_to have_key(:has_injectible_lines)
      expect(hash).not_to have_key(:injectible_lines)
    end
  end

  describe '#to_json' do
    it 'serializes scope to JSON string' do
      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
      )

      json = scope.to_json

      expect(json).to be_a(String)
      expect(JSON.parse(json)).to include(
        'scope_type' => 'CLASS',
        'name' => 'MyClass',
      )
    end

    it 'produces valid JSON for complex scope' do
      symbol = Datadog::SymbolDatabase::Symbol.new(
        symbol_type: 'FIELD',
        name: '@my_var',
        line: 5,
      )

      scope = described_class.new(
        scope_type: 'CLASS',
        name: 'MyClass',
        source_file: '/path/file.rb',
        start_line: 1,
        end_line: 50,
        language_specifics: {super_classes: ['BaseClass']},
        symbols: [symbol],
      )

      json = scope.to_json
      parsed = JSON.parse(json)

      expect(parsed['scope_type']).to eq('CLASS')
      expect(parsed['name']).to eq('MyClass')
      expect(parsed['source_file']).to eq('/path/file.rb')
      expect(parsed['symbols']).to be_an(Array)
      expect(parsed['symbols'].first['symbol_type']).to eq('FIELD')
    end
  end
end
