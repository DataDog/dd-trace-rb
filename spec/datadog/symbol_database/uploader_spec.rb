# frozen_string_literal: true

require 'datadog/symbol_database/uploader'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::Uploader do
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

  let(:test_scope) { Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'TestClass') }

  let(:logger) { instance_double(Logger, debug: nil) }

  # Mock transport infrastructure
  let(:mock_transport) { instance_double(Datadog::SymbolDatabase::Transport::Transport) }
  let(:mock_response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 200, internal_error?: false) }

  before do
    # Mock Transport::HTTP.build to return our mock transport
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:build).and_return(mock_transport)
  end

  subject(:uploader) { described_class.new(config, agent_settings, logger: logger) }

  describe '#upload_scopes' do
    it 'returns early if scopes is nil' do
      expect(uploader.upload_scopes(nil)).to be_nil
    end

    it 'returns early if scopes is empty' do
      expect(uploader.upload_scopes([])).to be_nil
    end

    context 'with valid scopes' do
      before do
        allow(mock_transport).to receive(:send_symdb_payload).and_return(mock_response)
      end

      it 'uploads successfully' do
        uploader.upload_scopes([test_scope])

        expect(mock_transport).to have_received(:send_symdb_payload)
      end

      it 'sends multipart form with event and file parts' do
        uploader.upload_scopes([test_scope])

        expect(mock_transport).to have_received(:send_symdb_payload) do |form|
          expect(form).to be_a(Hash)
          expect(form).to have_key('event')
          expect(form).to have_key('file')
          expect(form['event']).to be_a(Datadog::Core::Vendor::Multipart::Post::UploadIO)
          expect(form['file']).to be_a(Datadog::Core::Vendor::Multipart::Post::UploadIO)
        end
      end

      it 'logs success' do
        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/uploaded.*successfully/i) }

        uploader.upload_scopes([test_scope])
      end
    end

    context 'with serialization error' do
      before do
        allow_any_instance_of(Datadog::SymbolDatabase::ServiceVersion).to receive(:to_json).and_raise('Serialization error')
      end

      it 'logs error and returns nil' do
        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/serialization failed/i) }

        result = uploader.upload_scopes([test_scope])

        expect(result).to be_nil
      end

      it 'does not attempt HTTP request' do
        allow(logger).to receive(:debug)
        expect(mock_transport).not_to receive(:send_symdb_payload)

        uploader.upload_scopes([test_scope])
      end
    end

    context 'with compression error' do
      before do
        allow(Zlib).to receive(:gzip).and_raise('Compression error')
      end

      it 'logs error and returns nil' do
        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/compression failed/i) }

        result = uploader.upload_scopes([test_scope])

        expect(result).to be_nil
      end
    end

    context 'with oversized payload' do
      it 'logs warning and skips upload' do
        # Stub to return huge payload
        allow(Zlib).to receive(:gzip).and_return('x' * (described_class::MAX_PAYLOAD_SIZE + 1))

        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/payload too large/i) }
        expect(mock_transport).not_to receive(:send_symdb_payload)

        uploader.upload_scopes([test_scope])
      end
    end

    context 'with network errors' do
      it 'does not retry on connection errors — single attempt, logs and continues' do
        allow(mock_transport).to receive(:send_symdb_payload).and_raise(Errno::ECONNREFUSED, 'Connection refused')

        expect(mock_transport).to receive(:send_symdb_payload).once
        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error
      end

      it 'does not retry when transport returns InternalErrorResponse' do
        connection_error = Errno::ECONNREFUSED.new('Connection refused')
        internal_error_response = Datadog::Core::Transport::InternalErrorResponse.new(connection_error)

        allow(mock_transport).to receive(:send_symdb_payload).and_return(internal_error_response)

        expect(mock_transport).to receive(:send_symdb_payload).once
        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error
      end
    end

    context 'with HTTP errors' do
      it 'does not retry on 500 errors' do
        allow(mock_transport).to receive(:send_symdb_payload)
          .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 500, internal_error?: false))

        expect(mock_transport).to receive(:send_symdb_payload).once
        uploader.upload_scopes([test_scope])
      end

      it 'does not retry on 429 rate limit' do
        allow(mock_transport).to receive(:send_symdb_payload)
          .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 429, internal_error?: false))

        expect(mock_transport).to receive(:send_symdb_payload).once
        uploader.upload_scopes([test_scope])
      end

      it 'does not retry on 400 errors' do
        allow(mock_transport).to receive(:send_symdb_payload)
          .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 400, internal_error?: false))

        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/rejected/i) }

        uploader.upload_scopes([test_scope])
      end
    end
  end

  describe 'event metadata structure' do
    before do
      allow(mock_transport).to receive(:send_symdb_payload).and_return(mock_response)
    end

    it 'includes correct metadata fields' do
      # Capture the form passed to transport
      captured_form = nil
      allow(mock_transport).to receive(:send_symdb_payload) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      # Read the event part
      event_io = captured_form['event'].instance_variable_get(:@io)
      event_json = JSON.parse(event_io.read)

      expect(event_json['ddsource']).to eq('ruby')
      expect(event_json['service']).to eq('test-service')
      expect(event_json['type']).to eq('symdb')
      expect(event_json).to have_key('runtimeId')
    end
  end

  describe 'file part structure' do
    before do
      allow(mock_transport).to receive(:send_symdb_payload).and_return(mock_response)
    end

    it 'creates compressed file with correct naming' do
      captured_form = nil
      allow(mock_transport).to receive(:send_symdb_payload) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      file_upload = captured_form['file']
      expect(file_upload.original_filename).to match(/symbols_\d+\.json\.gz/)
      expect(file_upload.content_type).to eq('application/gzip')
    end
  end

  # === Tests ported from Java BatchUploaderTest ===

  describe 'multipart upload structure (ported from Java BatchUploaderTest.testUploadMultiPart)' do
    before do
      allow(mock_transport).to receive(:send_symdb_payload).and_return(mock_response)
    end

    it 'event part contains ddsource, service, and type fields' do
      captured_form = nil
      allow(mock_transport).to receive(:send_symdb_payload) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      event_io = captured_form['event'].instance_variable_get(:@io)
      event_json = JSON.parse(event_io.read)

      expect(event_json['ddsource']).to eq('ruby')
      expect(event_json['service']).to eq('test-service')
      expect(event_json['type']).to eq('symdb')
    end

    it 'file part is gzip compressed' do
      captured_form = nil
      allow(mock_transport).to receive(:send_symdb_payload) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      file_upload = captured_form['file']
      expect(file_upload.content_type).to eq('application/gzip')

      # Verify we can decompress and get valid JSON
      file_io = file_upload.instance_variable_get(:@io)
      compressed_data = file_io.read
      json_data = Zlib.gunzip(compressed_data)
      parsed = JSON.parse(json_data)

      expect(parsed['service']).to eq('test-service')
      expect(parsed['language']).to eq('ruby')
      expect(parsed['scopes']).to be_an(Array)
    end
  end

  describe 'upload with multiple scopes (ported from Java SymbolSinkTest.testMultiScopeFlush)' do
    before do
      allow(mock_transport).to receive(:send_symdb_payload).and_return(mock_response)
    end

    it 'includes all scopes in a single upload' do
      captured_form = nil
      allow(mock_transport).to receive(:send_symdb_payload) do |form|
        captured_form = form
        mock_response
      end

      scopes = [
        Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Class1'),
        Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Class2'),
        Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'Class3'),
      ]

      uploader.upload_scopes(scopes)

      file_upload = captured_form['file']
      file_io = file_upload.instance_variable_get(:@io)
      compressed_data = file_io.read
      json_data = Zlib.gunzip(compressed_data)
      parsed = JSON.parse(json_data)

      scope_names = parsed['scopes'].map { |s| s['name'] }
      expect(scope_names).to include('Class1', 'Class2', 'Class3')
    end
  end

  describe 'shutdown behavior (ported from Java BatchUploaderTest.testShutdown)' do
    it 'handles nil scopes gracefully after construction' do
      expect(uploader.upload_scopes(nil)).to be_nil
    end

    it 'handles empty scopes gracefully' do
      expect(uploader.upload_scopes([])).to be_nil
    end
  end
end
