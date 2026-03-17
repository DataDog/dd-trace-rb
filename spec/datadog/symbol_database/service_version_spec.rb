# frozen_string_literal: true

require 'datadog/symbol_database/service_version'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::ServiceVersion do
  describe '#initialize' do
    it 'creates service version with required fields' do
      sv = described_class.new(
        service: 'my-service',
        env: 'production',
        version: '1.0.0',
        scopes: []
      )

      expect(sv.service).to eq('my-service')
      expect(sv.env).to eq('production')
      expect(sv.version).to eq('1.0.0')
      expect(sv.language).to eq('JAVA')
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
      sv = described_class.new(service: 'svc', env: '', version: '1.0', scopes: [])
      expect(sv.env).to eq('none')
    end

    it 'converts nil env to "none"' do
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

    it 'sets language' do # TEMPORARY: expects JAVA, revert to RUBY after debugger-backend#1974
      sv = described_class.new(service: 'svc', env: 'prod', version: '1.0', scopes: [])
      expect(sv.language).to eq('JAVA')
    end
  end

  describe '#to_h' do
    it 'converts service version to hash' do
      sv = described_class.new(
        service: 'my-app',
        env: 'staging',
        version: '2.1.0',
        scopes: []
      )

      hash = sv.to_h

      expect(hash).to eq({
        service: 'my-app',
        env: 'staging',
        version: '2.1.0',
        language: 'JAVA',
        scopes: []
      })
    end

    it 'serializes scopes recursively' do
      scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'CLASS',
        name: 'MyClass'
      )

      sv = described_class.new(
        service: 'svc',
        env: 'prod',
        version: '1.0',
        scopes: [scope]
      )

      hash = sv.to_h

      expect(hash[:scopes]).to be_an(Array)
      expect(hash[:scopes].size).to eq(1)
      expect(hash[:scopes].first).to include(
        scope_type: 'CLASS',
        name: 'MyClass'
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
        scopes: []
      )

      json = sv.to_json

      expect(json).to be_a(String)
      parsed = JSON.parse(json)

      expect(parsed).to include(
        'service' => 'test-service',
        'env' => 'test',
        'version' => '0.1.0',
        'language' => 'JAVA',
        'scopes' => []
      )
    end

    it 'produces valid JSON for complete payload' do
      scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'MODULE',
        name: 'MyApp',
        source_file: '/app/lib/my_app.rb',
        start_line: 1,
        end_line: 100,
        language_specifics: {file_hash: 'abc123'}
      )

      sv = described_class.new(
        service: 'my-app',
        env: 'production',
        version: '1.0.0',
        scopes: [scope]
      )

      json = sv.to_json
      parsed = JSON.parse(json)

      expect(parsed['service']).to eq('my-app')
      expect(parsed['language']).to eq('JAVA')
      expect(parsed['scopes']).to be_an(Array)
      expect(parsed['scopes'].first['scope_type']).to eq('MODULE')
      expect(parsed['scopes'].first['language_specifics']['file_hash']).to eq('abc123')
    end
  end
end
