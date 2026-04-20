# frozen_string_literal: true

require 'datadog/symbol_database/service_version'

RSpec.describe Datadog::SymbolDatabase::ServiceVersion do
  describe '#initialize' do
    it 'stores required fields and defaults language to ruby' do
      payload = described_class.new(
        service: 'my-service',
        env: 'production',
        version: '1.0.0',
        scopes: [],
      )

      expect(payload.service).to eq('my-service')
      expect(payload.env).to eq('production')
      expect(payload.version).to eq('1.0.0')
      expect(payload.language).to eq('ruby')
      expect(payload.scopes).to eq([])
    end

    it 'normalizes blank env and version to none' do
      payload = described_class.new(
        service: 'my-service',
        env: '',
        version: nil,
        scopes: [],
      )

      expect(payload.env).to eq('none')
      expect(payload.version).to eq('none')
    end

    it 'rejects missing service' do
      expect do
        described_class.new(service: '', env: 'prod', version: '1.0', scopes: [])
      end.to raise_error(ArgumentError, /service is required/)
    end

    it 'rejects non-array scopes' do
      expect do
        described_class.new(service: 'svc', env: 'prod', version: '1.0', scopes: 'invalid')
      end.to raise_error(ArgumentError, /scopes must be an array/)
    end
  end

  describe '#to_h' do
    it 'serializes nested scopes' do
      scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'CLASS',
        name: 'MyClass',
      )
      payload = described_class.new(
        service: 'my-app',
        env: 'staging',
        version: '2.1.0',
        scopes: [scope],
      )

      expect(payload.to_h).to eq({
        service: 'my-app',
        env: 'staging',
        version: '2.1.0',
        language: 'ruby',
        scopes: [
          {
            scope_type: 'CLASS',
            name: 'MyClass',
          },
        ],
      })
    end
  end

  describe '#to_json' do
    it 'serializes the upload payload to JSON' do
      payload = described_class.new(
        service: 'test-service',
        env: 'test',
        version: '0.1.0',
        scopes: [],
      )

      expect(JSON.parse(payload.to_json)).to eq({
        'service' => 'test-service',
        'env' => 'test',
        'version' => '0.1.0',
        'language' => 'ruby',
        'scopes' => [],
      })
    end
  end
end
