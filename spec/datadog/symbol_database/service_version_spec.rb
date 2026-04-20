# frozen_string_literal: true

# DESIGN VERIFICATION SUMMARY FOR SERVICE VERSION TESTS:
#
# Tests verify behavior from:
#   - specs/json-schema.md (Top-Level: ServiceVersion, language values)
#   - design/json-serialization.md (validation, env/version defaults, language field)
#
# Test accuracy:
#   - Validation tests (nil service, empty service, non-array scopes): ACCURATE
#     per design/json-serialization.md lines 177-191
#   - env/version "none" defaults: ACCURATE per design/json-serialization.md line 186-187
#   - language = 'ruby': ACCURATE per specs/json-schema.md line 42
#   - "complete payload" test (line 144-169): Uses MODULE as top-level scope type.
#     Per specs/json-schema.md line 126, Ruby root scopes should be FILE. The test
#     is VALID for the data model (any scope type can be in the array) but does NOT
#     exercise the actual Ruby wire format. Also puts file_hash on a MODULE scope's
#     language_specifics -- per specs/json-schema.md line 228, "Ruby: No language_specifics
#     on MODULE scopes. File hash is on the parent FILE scope." The test data is
#     INACCURATE for Ruby protocol, though it correctly exercises serialization.
#   - schema_version: Correctly NOT tested (Python-only per spec). ACCURATE.

require 'datadog/symbol_database/service_version'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::ServiceVersion do
  describe '#initialize' do
    it 'creates service version with required fields' do
      sv = described_class.new(
        service: 'my-service',
        env: 'production',
        version: '1.0.0',
        scopes: [],
      )

      expect(sv.service).to eq('my-service')
      expect(sv.env).to eq('production')
      expect(sv.version).to eq('1.0.0')
      expect(sv.language).to eq('ruby')
      # DESIGN VERIFICATION: language 'ruby' (lowercase)
      #   Source: specs/json-schema.md line 42, 719 -- ACCURATE
      expect(sv.scopes).to eq([])
    end

    it 'raises ArgumentError when service is nil' do
      expect {
        described_class.new(service: nil, env: 'prod', version: '1.0', scopes: [])
      }.to raise_error(ArgumentError, /service is required/)
    end

    it 'raises ArgumentError when service is empty string' do
      expect {
        described_class.new(service: '', env: 'prod', version: '1.0', scopes: [])
      }.to raise_error(ArgumentError, /service is required/)
    end

    it 'raises ArgumentError when scopes is not an array' do
      expect {
        described_class.new(service: 'svc', env: 'prod', version: '1.0', scopes: 'invalid')
      }.to raise_error(ArgumentError, /scopes must be an array/)
    end

    it 'converts empty env to "none"' do
      # DESIGN VERIFICATION: design/json-serialization.md line 186 -- ACCURATE
      sv = described_class.new(service: 'svc', env: '', version: '1.0', scopes: [])
      expect(sv.env).to eq('none')
    end

    it 'converts nil env to "none"' do
      # DESIGN VERIFICATION: Implementation handles nil via .to_s.empty?.
      #   design/json-serialization.md only shows empty check, not nil.
      #   Implementation is MORE thorough. ACCURATE+.
      sv = described_class.new(service: 'svc', env: nil, version: '1.0', scopes: [])
      expect(sv.env).to eq('none')
    end

    it 'converts empty version to "none"' do
      sv = described_class.new(service: 'svc', env: 'prod', version: '', scopes: [])
      expect(sv.version).to eq('none')
    end

    it 'converts nil version to "none"' do
      sv = described_class.new(service: 'svc', env: 'prod', version: nil, scopes: [])
      expect(sv.version).to eq('none')
    end

    it 'sets language' do
      sv = described_class.new(service: 'svc', env: 'prod', version: '1.0', scopes: [])
      expect(sv.language).to eq('ruby')
    end
  end

  describe '#to_h' do
    it 'converts service version to hash' do
      sv = described_class.new(
        service: 'my-app',
        env: 'staging',
        version: '2.1.0',
        scopes: [],
      )

      hash = sv.to_h

      expect(hash).to eq({
        service: 'my-app',
        env: 'staging',
        version: '2.1.0',
        language: 'ruby',
        scopes: []
      })
    end

    it 'serializes scopes recursively' do
      scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'CLASS',
        name: 'MyClass',
      )

      sv = described_class.new(
        service: 'svc',
        env: 'prod',
        version: '1.0',
        scopes: [scope],
      )

      hash = sv.to_h

      expect(hash[:scopes]).to be_an(Array)
      expect(hash[:scopes].size).to eq(1)
      expect(hash[:scopes].first).to include(
        scope_type: 'CLASS',
        name: 'MyClass',
      )
    end

    it 'handles empty env as "none"' do
      sv = described_class.new(service: 'svc', env: '', version: '1.0', scopes: [])
      expect(sv.to_h[:env]).to eq('none')
    end

    it 'handles empty version as "none"' do
      sv = described_class.new(service: 'svc', env: 'prod', version: '', scopes: [])
      expect(sv.to_h[:version]).to eq('none')
    end
  end

  describe '#to_json' do
    it 'serializes to valid JSON string' do
      sv = described_class.new(
        service: 'test-service',
        env: 'test',
        version: '0.1.0',
        scopes: [],
      )

      json = sv.to_json

      expect(json).to be_a(String)
      parsed = JSON.parse(json)

      expect(parsed).to include(
        'service' => 'test-service',
        'env' => 'test',
        'version' => '0.1.0',
        'language' => 'ruby',
        'scopes' => [],
      )
    end

    it 'produces valid JSON for complete payload' do
      # DESIGN VERIFICATION: This test uses MODULE as root scope type with file_hash
      #   in language_specifics. Per specs/json-schema.md:
      #   - Line 126: Ruby root scope should be FILE, not MODULE
      #   - Line 228: "Ruby: No language_specifics on MODULE scopes.
      #     File hash is on the parent FILE scope."
      #   The test is valid for serialization mechanics but uses INACCURATE
      #   Ruby protocol data (should be scope_type: 'FILE' with file_hash).
      scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'MODULE',
        name: 'MyApp',
        source_file: '/app/lib/my_app.rb',
        start_line: 1,
        end_line: 100,
        language_specifics: {file_hash: 'abc123'},
      )

      sv = described_class.new(
        service: 'my-app',
        env: 'production',
        version: '1.0.0',
        scopes: [scope],
      )

      json = sv.to_json
      parsed = JSON.parse(json)

      expect(parsed['service']).to eq('my-app')
      expect(parsed['language']).to eq('ruby')
      expect(parsed['scopes']).to be_an(Array)
      expect(parsed['scopes'].first['scope_type']).to eq('MODULE')
      expect(parsed['scopes'].first['language_specifics']['file_hash']).to eq('abc123')
    end
  end
end
