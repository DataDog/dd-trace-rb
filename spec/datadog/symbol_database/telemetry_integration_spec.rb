# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/component'
require 'datadog/symbol_database/uploader'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/logger'
require 'datadog/symbol_database/scope'

# Integration test: validates that telemetry calls use the correct API
# (method names, argument counts) against a real Telemetry::Component.
#
# This test exists because unit tests previously used non-verifying doubles
# that accepted a nonexistent `count` method, masking a NoMethodError that
# only surfaced when running against a real Rails app (demo-ruby).
RSpec.describe 'Symbol Database Telemetry Integration' do
  let(:telemetry) do
    instance_double(Datadog::Core::Telemetry::Component)
  end

  let(:config) do
    instance_double(
      Datadog::Core::Configuration::Settings,
      service: 'test-service',
      env: 'test',
      version: '1.0.0',
    )
  end

  let(:agent_settings) do
    instance_double(
      Datadog::Core::Configuration::AgentSettings,
      hostname: 'localhost',
      port: 8126,
      timeout_seconds: 30,
      ssl: false,
    )
  end

  let(:mock_transport) { instance_double(Datadog::SymbolDatabase::Transport::Transport) }
  let(:test_scope) { Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'TestClass') }

  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:build).and_return(mock_transport)
  end

  describe 'Uploader telemetry calls' do
    subject(:uploader) { Datadog::SymbolDatabase::Uploader.new(config, agent_settings, logger: instance_double(Logger, debug: nil), telemetry: telemetry) }

    it 'calls inc and distribution with correct signatures on successful upload' do
      allow(mock_transport).to receive(:send_symdb_payload)
        .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 200, internal_error?: false))

      expect(telemetry).to receive(:distribution).with('tracers', 'symbol_database.compression_ratio', a_kind_of(Numeric))
      expect(telemetry).to receive(:distribution).with('tracers', 'symbol_database.payload_size', a_kind_of(Integer))
      expect(telemetry).to receive(:inc).with('tracers', 'symbol_database.uploaded', 1)
      expect(telemetry).to receive(:inc).with('tracers', 'symbol_database.scopes_uploaded', 1)

      uploader.upload_scopes([test_scope])
    end

    it 'calls inc on upload error' do
      allow(mock_transport).to receive(:send_symdb_payload)
        .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 400, internal_error?: false))

      allow(telemetry).to receive(:distribution)
      expect(telemetry).to receive(:inc).with('tracers', 'symbol_database.upload_error', 1, tags: ['error:client_error'])

      uploader.upload_scopes([test_scope])
    end
  end

  describe 'ScopeBatcher telemetry calls' do
    let(:mock_uploader) { instance_double(Datadog::SymbolDatabase::Uploader) }

    let(:sc_settings) do
      s = double('settings')
      symdb = double('symbol_database', internal: double('internal', trace_logging: false))
      allow(s).to receive(:symbol_database).and_return(symdb)
      s
    end
    let(:sc_logger) { Datadog::SymbolDatabase::Logger.new(sc_settings, instance_double(Logger, debug: nil)) }

    subject(:scope_batcher) { Datadog::SymbolDatabase::ScopeBatcher.new(mock_uploader, logger: sc_logger, telemetry: telemetry, timer_enabled: false) }

    after { scope_batcher.reset }

    it 'does not raise on add_scope error path' do
      # Force an error by passing nil scope to trigger rescue path
      allow(telemetry).to receive(:inc)

      # A nil scope should be handled gracefully
      expect { scope_batcher.add_scope(nil) }.not_to raise_error
    end
  end
end
