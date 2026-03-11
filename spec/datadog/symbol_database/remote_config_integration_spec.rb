# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/component'
require 'datadog/symbol_database/remote'
require 'datadog/core/remote/configuration/repository'
require 'webmock/rspec'
require 'digest'

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
    end
  end

  let(:agent_settings) do
    double('agent_settings').tap do |as|
      allow(as).to receive(:hostname).and_return('localhost')
      allow(as).to receive(:port).and_return(8126)
      allow(as).to receive(:ssl).and_return(false)
      allow(as).to receive(:timeout_seconds).and_return(30)
    end
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

    # Use webmock to intercept HTTP requests
    stub_request(:post, %r{http://.*:8126/symdb/v1/input})
      .to_return do |request|
        # Capture request details
        upload_requests << {
          path: '/symdb/v1/input',
          headers: request.headers,
        }

        # Extract and decompress the uploaded file from multipart
        body_string = request.body

        # Parse multipart to find the gzipped JSON file
        # Multipart format: ...Content-Disposition: form-data; name="file"...
        if body_string =~ /Content-Disposition: form-data; name="file".*?\r\n\r\n(.+?)\r\n--/m
          gzipped_data = $1
          begin
            json_string = Zlib::GzipReader.new(StringIO.new(gzipped_data)).read
            uploaded_payloads << JSON.parse(json_string)
          rescue
            # Parsing failed, skip
          end
        end

        # Return success response
        {status: 200, body: '{}', headers: {}}
      end
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

  describe 'full remote config flow' do
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
        sleep 0.5

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
        expect(test_class_scope).not_to be_nil

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

        sleep 0.5

        expect(upload_requests).not_to be_empty

        request = upload_requests.first
        expect(request[:path]).to eq('/symdb/v1/input')
        expect(request[:headers]['Content-Type']).to match(/multipart\/form-data/)
        expect(request[:headers]['Content-Encoding']).to eq('gzip')
      end
    end

    context 'when upload_symbols: false is received' do
      it 'does not trigger upload' do
        simulate_rc_insert({upload_symbols: false})

        sleep 0.5

        expect(uploaded_payloads).to be_empty
      end
    end

    context 'when config is updated' do
      it 'stops and restarts upload' do
        # First insert with upload_symbols: true
        simulate_rc_insert({upload_symbols: true})
        sleep 0.5

        initial_uploads = uploaded_payloads.length
        expect(initial_uploads).to be > 0

        # Update with new config
        simulate_rc_insert({upload_symbols: true})
        sleep 0.5

        # Should have triggered another upload
        expect(uploaded_payloads.length).to be > initial_uploads
      end
    end

    context 'when config is deleted' do
      it 'stops upload' do
        # Insert config
        simulate_rc_insert({upload_symbols: true})
        sleep 0.5

        initial_uploads = uploaded_payloads.length
        expect(initial_uploads).to be > 0

        # Delete config
        simulate_rc_delete
        sleep 0.5

        # Clear the payloads array
        uploaded_payloads.clear

        # Wait a bit to ensure no new uploads
        sleep 0.5

        expect(uploaded_payloads).to be_empty
      end
    end

    context 'when config is invalid' do
      it 'handles missing upload_symbols key gracefully' do
        expect(logger).to receive(:debug).with(/Missing 'upload_symbols' key/)

        simulate_rc_insert({some_other_key: true})

        sleep 0.5

        expect(uploaded_payloads).to be_empty
      end

      it 'handles invalid config format gracefully' do
        expect(logger).to receive(:debug).with(/Invalid config format/)

        simulate_rc_insert('not a hash')

        sleep 0.5

        expect(uploaded_payloads).to be_empty
      end
    end
  end

  describe 'cooldown period' do
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
      sleep 0.5

      first_upload_count = uploaded_payloads.length
      expect(first_upload_count).to be > 0

      # Try to trigger again immediately
      simulate_rc_insert({upload_symbols: true})
      sleep 0.5

      # Should NOT have uploaded again due to cooldown
      expect(uploaded_payloads.length).to eq(first_upload_count)
    end
  end

  describe 'force upload mode' do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.symbol_database.enabled = true
        s.symbol_database.force_upload = true
        s.remote.enabled = false  # Force mode bypasses remote config
        s.service = 'rspec'
        s.env = 'test'
        s.version = '1.0.0'
      end
    end

    it 'uploads immediately without remote config' do
      component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)

      # Give extraction time to complete
      sleep 0.5

      # Should have uploaded despite remote config disabled
      expect(uploaded_payloads).not_to be_empty

      payload = uploaded_payloads.first
      expect(payload['service']).to eq('rspec')
      expect(payload['scopes']).to be_an(Array)

      component.shutdown!
    end
  end

  describe 'component lifecycle' do
    let(:component) do
      Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: telemetry)
    end

    it 'cleans up on shutdown' do
      components = double('components')
      allow(components).to receive(:symbol_database).and_return(component)
      allow(Datadog).to receive(:send).with(:components).and_return(components)

      simulate_rc_insert({upload_symbols: true})
      sleep 0.5

      expect(uploaded_payloads).not_to be_empty

      # Shutdown should complete without error
      expect { component.shutdown! }.not_to raise_error
    end

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
      # Make upload fail
      allow_any_instance_of(Datadog::SymbolDatabase::Uploader).to receive(:send_request).and_raise(StandardError.new('Network error'))

      expect(logger).to receive(:debug).with(/Error uploading symbols/)

      simulate_rc_insert({upload_symbols: true})
      sleep 0.5

      # Should not crash, error should be logged
    end

    it 'handles extraction errors gracefully' do
      # Mock extractor to raise error
      allow(Datadog::SymbolDatabase::Extractor).to receive(:extract).and_raise(StandardError.new('Extraction error'))

      expect(logger).to receive(:debug).with(/Error during extraction/)

      simulate_rc_insert({upload_symbols: true})
      sleep 0.5

      # Should not crash
    end
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
end
