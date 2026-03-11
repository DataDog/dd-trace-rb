# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/component'
require 'datadog/symbol_database/remote'
require 'datadog/core/remote/configuration/repository'
require 'digest'
require 'zlib'

# Test class to verify symbol extraction
class RemoteConfigIntegrationTestClass
  CONSTANT = 42
  @@class_var = 'test'

  def instance_method(arg1, arg2)
    arg1 + arg2
  end

  def self.class_method
    'result'
  end
end

RSpec.describe 'Symbol Database Remote Config Integration' do
  let(:logger) { instance_double(Logger) }
  let(:telemetry) { nil }  # Telemetry is optional

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.remote.enabled = true
      s.service = 'rspec'
      s.env = 'test'
      s.version = '1.0.0'
      s.agent.host = 'localhost'
      s.agent.port = defined?(http_server_port) ? http_server_port : 8126
    end
  end

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end

  let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

  let(:receiver) { Datadog::SymbolDatabase::Remote.receivers(telemetry)[0] }

  # Capture uploaded payloads
  let(:uploaded_payloads) { [] }
  let(:upload_requests) { [] }

  before do
    # Stub logger to avoid noise
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  # Helper to simulate RC insert
  def simulate_rc_insert(content)
    config_path = 'datadog/2/LIVE_DEBUGGING_SYMBOL_DB/test/config'

    changes = repository.transaction do |_repository, transaction|
      content_json = content.to_json

      target = Datadog::Core::Remote::Configuration::Target.parse(
        {
          'custom' => {'v' => 1},
          'hashes' => {'sha256' => Digest::SHA256.hexdigest(content_json)},
          'length' => content_json.length,
        }
      )

      rc_content = Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: config_path,
          content: content_json,
        }
      )

      transaction.insert(rc_content.path, target, rc_content)
    end

    receiver.call(repository, changes)
  end

  # Helper to simulate RC delete
  def simulate_rc_delete
    config_path = 'datadog/2/LIVE_DEBUGGING_SYMBOL_DB/test/config'

    changes = repository.transaction do |_repository, transaction|
      content_json = {}.to_json

      target = Datadog::Core::Remote::Configuration::Target.parse(
        {
          'custom' => {'v' => 1},
          'hashes' => {'sha256' => Digest::SHA256.hexdigest(content_json)},
          'length' => content_json.length,
        }
      )

      rc_content = Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: config_path,
          content: content_json,
        }
      )

      transaction.delete(rc_content.path, target, rc_content)
    end

    receiver.call(repository, changes)
  end

  # Helper to parse multipart body and extract gzipped JSON
  def extract_json_from_multipart(body)
    # Find the file part with gzipped JSON
    # WEBrick might give us the body as a string or a Tempfile
    body_str = body.is_a?(String) ? body : body.read

    # Split multipart by boundary
    # Format: Content-Disposition: form-data; name="file"; filename="symbols_PID.json.gz"
    # Try different boundary patterns
    if body_str =~ /Content-Disposition: form-data; name="file".*?\r\n\r\n(.+?)\r\n----/m ||
       body_str =~ /Content-Disposition: form-data; name="file".*?\n\n(.+?)\n----/m
      gzipped_data = $1
      json_string = Zlib::GzipReader.new(StringIO.new(gzipped_data)).read
      JSON.parse(json_string)
    end
  rescue => e
    puts "DEBUG: Failed to parse multipart: #{e.class}: #{e.message}"
    puts "DEBUG: Body length: #{body_str&.length}"
    puts "DEBUG: Body preview: #{body_str[0..200]}" if body_str
    nil
  end

  # Helper to find a scope by name in nested structure
  def find_scope_by_name(scopes, name)
    scopes.each do |scope|
      return scope if scope['name'] == name

      # Check nested scopes recursively
      if scope['scopes']
        found = find_scope_by_name(scope['scopes'], name)
        return found if found
      end
    end
    nil
  end

  describe 'full remote config flow' do
    http_server do |http_server|
      http_server.mount_proc('/symdb/v1/input') do |req, res|
        upload_requests << {
          path: req.path,
          content_type: req.content_type,
          headers: req.header,
        }

        # Parse multipart body
        payload = extract_json_from_multipart(req.body)
        uploaded_payloads << payload if payload

        res.status = 200
        res.body = '{}'
      end
    end

    let(:component) do
      Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)
    end

    before do
      # Mock Datadog.send(:components) to return object with symbol_database
      components = double('components')
      allow(components).to receive(:symbol_database).and_return(component)
      allow(Datadog).to receive(:send).with(:components).and_return(components)
    end

    after do
      component&.shutdown!
    end

    context 'when upload_symbols: true is received' do
      it 'extracts and uploads symbols' do
        # Simulate RC sending upload_symbols: true
        simulate_rc_insert({upload_symbols: true})

        # Give extraction time to complete
        sleep 1

        # Verify upload was triggered
        expect(uploaded_payloads).not_to be_empty

        payload = uploaded_payloads.first

        # Verify ServiceVersion structure
        expect(payload['service']).to eq('rspec')
        expect(payload['env']).to eq('test')
        expect(payload['version']).to eq('1.0.0')
        expect(payload['language']).to eq('RUBY')
        expect(payload['scopes']).to be_an(Array)

        # Verify we have scopes
        expect(payload['scopes'].length).to be > 0

        # Find our test class in the uploaded scopes
        test_class_scope = find_scope_by_name(payload['scopes'], 'RemoteConfigIntegrationTestClass')

        if test_class_scope
          # Verify class structure
          expect(test_class_scope['scope_type']).to eq('CLASS')

          # Verify methods were extracted
          method_names = (test_class_scope['scopes'] || []).map { |s| s['name'] }
          expect(method_names).to include('instance_method')
          expect(method_names).to include('self.class_method')

          # Verify class variable was extracted
          symbol_names = (test_class_scope['symbols'] || []).map { |s| s['name'] }
          expect(symbol_names).to include('@@class_var')
        end
      end

      it 'includes correct HTTP headers' do
        simulate_rc_insert({upload_symbols: true})

        sleep 1

        expect(upload_requests).not_to be_empty

        request = upload_requests.first
        expect(request[:path]).to eq('/symdb/v1/input')
        expect(request[:content_type]).to match(/multipart\/form-data/)
      end
    end

    context 'when upload_symbols: false is received' do
      it 'does not trigger upload' do
        simulate_rc_insert({upload_symbols: false})

        sleep 1

        expect(uploaded_payloads).to be_empty
      end
    end

    context 'when config is updated' do
      it 'stops and restarts upload' do
        # First insert with upload_symbols: true
        simulate_rc_insert({upload_symbols: true})
        sleep 1

        initial_uploads = uploaded_payloads.length
        expect(initial_uploads).to be > 0

        # Update with new config (should trigger stop then start)
        # But cooldown prevents immediate re-upload
        simulate_rc_insert({upload_symbols: true})
        sleep 1

        # Due to cooldown, should NOT have triggered another upload immediately
        expect(uploaded_payloads.length).to eq(initial_uploads)
      end
    end

    context 'when config is deleted' do
      it 'stops upload' do
        # Insert config
        simulate_rc_insert({upload_symbols: true})
        sleep 1

        initial_uploads = uploaded_payloads.length
        expect(initial_uploads).to be > 0

        # Delete config
        simulate_rc_delete

        # Clear the payloads array
        uploaded_payloads.clear

        # Wait a bit to ensure no new uploads
        sleep 1

        expect(uploaded_payloads).to be_empty
      end
    end

    context 'when config is invalid' do
      it 'handles missing upload_symbols key gracefully' do
        expect(logger).to receive(:debug).with(/Missing 'upload_symbols' key/)

        simulate_rc_insert({some_other_key: true})

        sleep 1

        expect(uploaded_payloads).to be_empty
      end

      it 'handles invalid config format gracefully' do
        expect(logger).to receive(:debug).with(/Invalid config format/)

        simulate_rc_insert('not a hash')

        sleep 1

        expect(uploaded_payloads).to be_empty
      end
    end
  end

  describe 'cooldown period' do
    http_server do |http_server|
      http_server.mount_proc('/symdb/v1/input') do |req, res|
        payload = extract_json_from_multipart(req.body)
        uploaded_payloads << payload if payload

        res.status = 200
        res.body = '{}'
      end
    end

    let(:component) do
      Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)
    end

    before do
      components = double('components')
      allow(components).to receive(:symbol_database).and_return(component)
      allow(Datadog).to receive(:send).with(:components).and_return(components)
    end

    after do
      component&.shutdown!
    end

    it 'prevents rapid re-uploads within 60 seconds' do
      # First upload
      simulate_rc_insert({upload_symbols: true})
      sleep 1

      first_upload_count = uploaded_payloads.length
      expect(first_upload_count).to be > 0

      # Try to trigger again immediately
      component.start_upload
      sleep 1

      # Should NOT have uploaded again due to cooldown
      expect(uploaded_payloads.length).to eq(first_upload_count)
    end
  end

  describe 'force upload mode' do
    http_server do |http_server|
      http_server.mount_proc('/symdb/v1/input') do |req, res|
        payload = extract_json_from_multipart(req.body)
        uploaded_payloads << payload if payload

        res.status = 200
        res.body = '{}'
      end
    end

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.symbol_database.enabled = true
        s.symbol_database.force_upload = true
        s.remote.enabled = false  # Force mode bypasses remote config
        s.service = 'rspec'
        s.env = 'test'
        s.version = '1.0.0'
        s.agent.host = 'localhost'
        s.agent.port = http_server_port
      end
    end

    it 'uploads immediately without remote config' do
      component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)

      # Give extraction time to complete
      # Extraction runs async, timer fires after 1s of inactivity
      sleep 2.5

      # Should have uploaded despite remote config disabled
      expect(uploaded_payloads).not_to be_empty, "No payloads were uploaded. Debug: #{upload_requests.length} requests received"

      payload = uploaded_payloads.first
      expect(payload['service']).to eq('rspec')
      expect(payload['scopes']).to be_an(Array)

      component.shutdown!
    end
  end

  describe 'component lifecycle' do
    it 'returns nil when symbol_database disabled' do
      settings.symbol_database.enabled = false

      component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)

      expect(component).to be_nil
    end

    it 'returns nil when remote config disabled and not force mode' do
      settings.remote.enabled = false
      settings.symbol_database.force_upload = false

      component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)

      expect(component).to be_nil
    end
  end

  describe 'error resilience' do
    http_server do |http_server|
      http_server.mount_proc('/symdb/v1/input') do |req, res|
        # Simulate server error
        res.status = 500
        res.body = 'Internal Server Error'
      end
    end

    let(:component) do
      Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)
    end

    before do
      components = double('components')
      allow(components).to receive(:symbol_database).and_return(component)
      allow(Datadog).to receive(:send).with(:components).and_return(components)
    end

    after do
      component&.shutdown!
    end

    it 'handles upload failures gracefully' do
      expect(logger).to receive(:debug).with(/Error uploading symbols/)

      simulate_rc_insert({upload_symbols: true})
      sleep 1

      # Should not crash, error should be logged
    end
  end
end
