# frozen_string_literal: true

require 'json'
require 'datadog/symbol_database/service_version'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::ServiceVersion do
  describe '#to_h' do
    it 'includes required fields' do
      sv = described_class.new(service: 'test-svc', env: 'prod', version: '1.0')
      h = sv.to_h
      expect(h[:service]).to eq('test-svc')
      expect(h[:env]).to eq('prod')
      expect(h[:version]).to eq('1.0')
      expect(h[:language]).to eq('RUBY')
    end

    it 'omits scopes when empty' do
      sv = described_class.new(service: 's', env: 'e', version: 'v', scopes: [])
      expect(sv.to_h).not_to have_key(:scopes)
    end

    it 'includes scopes when present' do
      scope = Datadog::SymbolDatabase::Scope.new(scope_type: 'MODULE', name: 'test')
      sv = described_class.new(service: 's', env: 'e', version: 'v', scopes: [scope])
      expect(sv.to_h[:scopes]).to be_an(Array)
      expect(sv.to_h[:scopes].first[:scope_type]).to eq('MODULE')
    end
  end

  describe '#to_json' do
    it 'produces valid JSON' do
      sv = described_class.new(service: 'test', env: 'dev', version: '1.0')
      json = sv.to_json
      parsed = JSON.parse(json)
      expect(parsed['service']).to eq('test')
      expect(parsed['language']).to eq('RUBY')
    end
  end
end
