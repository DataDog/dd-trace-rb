# frozen_string_literal: true

require 'datadog/symbol_database/uploader'
require 'datadog/symbol_database/scope'

RSpec.describe Datadog::SymbolDatabase::Uploader do
  let(:config) do
    double('config',
      service: 'test-service',
      env: 'test',
      version: '1.0.0',
      api_key: 'test_api_key')
  end

  let(:agent_settings) do
    double('agent_settings',
      hostname: 'localhost',
      port: 8126,
      timeout_seconds: 30,
      ssl: false)
  end

  let(:test_scope) { Datadog::SymbolDatabase::Scope.new(scope_type: 'CLASS', name: 'TestClass') }

  # Mock transport infrastructure
  let(:mock_transport) { double('transport') }
  let(:mock_response) { double('response', code: 200) }

  before do
    # Mock Transport::HTTP.build to return our mock transport
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:build).and_return(mock_transport)
  end

  subject(:uploader) { described_class.new(config, agent_settings) }

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
        expect(Datadog.logger).to receive(:debug).with(/Uploaded.*successfully/)

        uploader.upload_scopes([test_scope])
      end
    end

    context 'with serialization error' do
      before do
        allow_any_instance_of(Datadog::SymbolDatabase::ServiceVersion).to receive(:to_json).and_raise('Serialization error')
      end

      it 'logs error and returns nil' do
        expect(Datadog.logger).to receive(:debug).with(/Serialization failed/)

        result = uploader.upload_scopes([test_scope])

        expect(result).to be_nil
      end

      it 'does not attempt HTTP request' do
        allow(Datadog.logger).to receive(:debug)
        expect(mock_transport).not_to receive(:send_symdb_payload)

        uploader.upload_scopes([test_scope])
      end
    end

    context 'with compression error' do
      before do
        allow(Zlib).to receive(:gzip).and_raise('Compression error')
      end

      it 'logs error and returns nil' do
        expect(Datadog.logger).to receive(:debug).with(/Compression failed/)

        result = uploader.upload_scopes([test_scope])

        expect(result).to be_nil
      end
    end

    context 'with oversized payload' do
      it 'logs warning and skips upload' do
        # Stub to return huge payload
        allow(Zlib).to receive(:gzip).and_return('x' * (described_class::MAX_PAYLOAD_SIZE + 1))

        expect(Datadog.logger).to receive(:debug).with(/Payload too large/)
        expect(mock_transport).not_to receive(:send_symdb_payload)

        uploader.upload_scopes([test_scope])
      end
    end

    context 'with network errors' do
      it 'retries on connection errors' do
        attempt = 0
        allow(mock_transport).to receive(:send_symdb_payload) do
          attempt += 1
          if attempt < 3
            raise Errno::ECONNREFUSED, 'Connection refused'
          else
            double('response', code: '200')
          end
        end

        # Should not raise, should retry and eventually succeed
        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error
        expect(attempt).to eq(3)
      end

      it 'gives up after MAX_RETRIES' do
        attempt = 0
        allow(mock_transport).to receive(:send_symdb_payload) do
          attempt += 1
          raise Errno::ECONNREFUSED, 'Connection refused'
        end

        # Should not raise, should log and give up
        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error

        # Should have tried MAX_RETRIES + 1 times (initial + retries)
        expect(attempt).to eq(11)  # MAX_RETRIES = 10, so 1 + 10 = 11
      end
    end

    context 'with HTTP errors' do
      it 'retries on 500 errors' do
        attempt = 0
        allow(mock_transport).to receive(:send_symdb_payload) do
          attempt += 1
          if attempt < 3
            double('response', code: 500)
          else
            double('response', code: 200)
          end
        end

        uploader.upload_scopes([test_scope])

        expect(attempt).to eq(3)
      end

      it 'retries on 429 rate limit' do
        attempt = 0
        allow(mock_transport).to receive(:send_symdb_payload) do
          attempt += 1
          if attempt < 2
            double('response', code: 429)
          else
            double('response', code: 200)
          end
        end

        uploader.upload_scopes([test_scope])

        expect(attempt).to eq(2)
      end

      it 'does not retry on 400 errors' do
        allow(mock_transport).to receive(:send_symdb_payload).and_return(double('response', code: 400))

        expect(Datadog.logger).to receive(:debug).with(/rejected/)

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

  describe '#calculate_backoff' do
    it 'uses exponential backoff' do
      backoff1 = uploader.send(:calculate_backoff, 1)
      backoff2 = uploader.send(:calculate_backoff, 2)
      backoff3 = uploader.send(:calculate_backoff, 3)

      # Should roughly double each time (with jitter)
      expect(backoff2).to be > backoff1
      expect(backoff3).to be > backoff2
    end

    it 'caps at MAX_BACKOFF_INTERVAL' do
      backoff = uploader.send(:calculate_backoff, 20)

      expect(backoff).to be <= described_class::MAX_BACKOFF_INTERVAL
    end

    it 'adds jitter' do
      # Run multiple times, should get different values due to jitter
      backoffs = 10.times.map { uploader.send(:calculate_backoff, 1) }

      expect(backoffs.uniq.size).to be > 1
    end
  end
end
