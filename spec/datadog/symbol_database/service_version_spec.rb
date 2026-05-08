# frozen_string_literal: true

require 'datadog/symbol_database/service_version'
require 'datadog/symbol_database/scope'
require 'datadog/symbol_database/symbol'

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

    it 'passes empty env through unchanged' do
      sv = described_class.new(service: 'svc', env: '', version: '1.0', scopes: [])
      expect(sv.env).to eq('')
    end

    it 'passes nil env through unchanged' do
      sv = described_class.new(service: 'svc', env: nil, version: '1.0', scopes: [])
      expect(sv.env).to be_nil
    end

    it 'passes empty version through unchanged' do
      sv = described_class.new(service: 'svc', env: 'prod', version: '', scopes: [])
      expect(sv.version).to eq('')
    end

    it 'passes nil version through unchanged' do
      sv = described_class.new(service: 'svc', env: 'prod', version: nil, scopes: [])
      expect(sv.version).to be_nil
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

      expect(sv.to_h).to eq({
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

    it 'passes empty env through to the hash' do
      sv = described_class.new(service: 'svc', env: '', version: '1.0', scopes: [])
      expect(sv.to_h[:env]).to eq('')
    end

    it 'passes nil version through to the hash' do
      sv = described_class.new(service: 'svc', env: 'prod', version: nil, scopes: [])
      expect(sv.to_h[:version]).to be_nil
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

    it 'produces valid JSON for complete Ruby payload' do
      method_scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'METHOD',
        name: 'remember',
        source_file: '/app/models/user.rb',
        start_line: 5,
        end_line: 7,
        injectible_lines: [{start: 6, end: 7}],
        language_specifics: {visibility: 'public', method_type: 'instance'},
        symbols: [
          Datadog::SymbolDatabase::Symbol.new(symbol_type: 'ARG', name: 'token', line: 5),
        ],
      )

      class_scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'CLASS',
        name: 'User',
        source_file: '/app/models/user.rb',
        start_line: 1,
        end_line: 8,
        language_specifics: {super_classes: ['ApplicationRecord']},
        scopes: [method_scope],
      )

      file_scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'FILE',
        name: '/app/models/user.rb',
        source_file: '/app/models/user.rb',
        start_line: 0,
        end_line: 2147483647,
        language_specifics: {file_hash: 'abc123'},
        scopes: [class_scope],
      )

      sv = described_class.new(
        service: 'my-app',
        env: 'production',
        version: '1.0.0',
        scopes: [file_scope],
      )

      json = sv.to_json
      parsed = JSON.parse(json)

      expect(parsed['service']).to eq('my-app')
      expect(parsed['language']).to eq('ruby')
      expect(parsed['scopes']).to be_an(Array)
      expect(parsed['scopes'].size).to eq(1)

      file = parsed['scopes'].first
      expect(file['scope_type']).to eq('FILE')
      expect(file['language_specifics']['file_hash']).to eq('abc123')

      klass = file['scopes'].first
      expect(klass['scope_type']).to eq('CLASS')
      expect(klass['name']).to eq('User')
      expect(klass['language_specifics']['super_classes']).to eq(['ApplicationRecord'])

      method = klass['scopes'].first
      expect(method['scope_type']).to eq('METHOD')
      expect(method['name']).to eq('remember')
      expect(method['has_injectible_lines']).to eq(true)
      expect(method['injectible_lines']).to eq([{'start' => 6, 'end' => 7}])
      expect(method['symbols'].first['symbol_type']).to eq('ARG')
      expect(method['symbols'].first['name']).to eq('token')
    end
  end
end
