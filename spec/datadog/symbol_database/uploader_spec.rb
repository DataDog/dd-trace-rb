# frozen_string_literal: true

require "datadog/symbol_database/uploader"
require "datadog/symbol_database/scope"

RSpec.describe Datadog::SymbolDatabase::Uploader do
  let(:settings) do
    instance_double(
      Datadog::Core::Configuration::Settings,
      service: "test-service",
      env: "test",
      version: "1.0.0"
    )
  end

  let(:agent_settings) do
    instance_double(
      Datadog::Core::Configuration::AgentSettings,
      hostname: "localhost",
      port: 8126,
      timeout_seconds: 30,
      ssl: false
    )
  end

  let(:test_scope) { Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "TestClass") }

  let(:logger) { instance_double(Logger, debug: nil) }
  let(:telemetry) { nil }

  let(:mock_transport) { instance_double(Datadog::SymbolDatabase::Transport::Symbols::Transport) }
  let(:mock_response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 200, internal_error?: false) }

  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:symbols).and_return(mock_transport)
  end

  subject(:uploader) do
    described_class.new(settings: settings, agent_settings: agent_settings, logger: logger, telemetry: telemetry)
  end

  describe "#upload_scopes" do
    it "returns early if scopes is empty" do
      expect(mock_transport).not_to receive(:send_symbols)
      uploader.upload_scopes([])
    end

    context "with valid scopes" do
      before do
        allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
      end

      it "uploads successfully" do
        uploader.upload_scopes([test_scope])

        expect(mock_transport).to have_received(:send_symbols)
      end

      it "sends multipart form with event and file parts" do
        uploader.upload_scopes([test_scope])

        expect(mock_transport).to have_received(:send_symbols) do |form|
          expect(form).to be_a(Hash)
          expect(form).to have_key("event")
          expect(form).to have_key("file")
          expect(form["event"]).to be_a(Datadog::Core::Vendor::Multipart::Post::UploadIO)
          expect(form["file"]).to be_a(Datadog::Core::Vendor::Multipart::Post::UploadIO)
        end
      end

      it "logs success" do
        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/uploaded.*successfully/i) }

        uploader.upload_scopes([test_scope])
      end
    end

    context "when payload construction raises" do
      before do
        allow_any_instance_of(Datadog::SymbolDatabase::ServiceVersion).to receive(:to_json).and_raise("Serialization error")
      end

      it "is caught by the outer rescue, logs at debug, and does not raise" do
        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/upload failed.*Serialization error/) }
        expect(mock_transport).not_to receive(:send_symbols)

        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error
      end

      context "when telemetry is provided" do
        let(:telemetry) { instance_double("Datadog::Core::Telemetry::Component", report: nil) }

        it "reports the error via telemetry" do
          allow(logger).to receive(:debug)
          expect(telemetry).to receive(:report).with(an_instance_of(RuntimeError), description: "symdb: upload failed")

          uploader.upload_scopes([test_scope])
        end
      end
    end

    context "with oversized payload" do
      it "logs warning and skips upload" do
        # Stub to return huge payload
        allow(Zlib).to receive(:gzip).and_return("x" * (described_class::MAX_PAYLOAD_SIZE + 1))

        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/payload too large/i) }
        expect(mock_transport).not_to receive(:send_symbols)

        uploader.upload_scopes([test_scope])
      end
    end

    context "with telemetry payload size metric" do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, distribution: nil, report: nil) }

      it "emits payload_size distribution on successful upload with compressed bytesize" do
        allow(mock_transport).to receive(:send_symbols).and_return(mock_response)

        captured_size = nil
        allow(Zlib).to receive(:gzip).and_wrap_original do |orig, *args|
          result = orig.call(*args)
          captured_size = result.bytesize
          result
        end

        uploader.upload_scopes([test_scope])

        expect(telemetry).to have_received(:distribution)
          .with("tracers", "symbol_database.payload_size", captured_size)
      end

      it "emits payload_size distribution on the oversized-skip path" do
        oversized = "x" * (described_class::MAX_PAYLOAD_SIZE + 1)
        allow(Zlib).to receive(:gzip).and_return(oversized)
        expect(mock_transport).not_to receive(:send_symbols)

        uploader.upload_scopes([test_scope])

        expect(telemetry).to have_received(:distribution)
          .with("tracers", "symbol_database.payload_size", oversized.bytesize)
      end

      it "does not emit payload_size when serialization raises before compression" do
        allow_any_instance_of(Datadog::SymbolDatabase::ServiceVersion)
          .to receive(:to_json).and_raise("Serialization error")

        uploader.upload_scopes([test_scope])

        expect(telemetry).not_to have_received(:distribution)
      end

      it "does not emit payload_size when compression itself raises" do
        allow(Zlib).to receive(:gzip).and_raise(Zlib::Error, "compress failed")

        uploader.upload_scopes([test_scope])

        expect(telemetry).not_to have_received(:distribution)
      end
    end

    context "with network errors" do
      it "does not retry on connection errors — single attempt, logs and continues" do
        allow(mock_transport).to receive(:send_symbols).and_raise(Errno::ECONNREFUSED, "Connection refused")

        expect(mock_transport).to receive(:send_symbols).once
        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error
      end

      it "does not retry when transport returns InternalErrorResponse" do
        connection_error = Errno::ECONNREFUSED.new("Connection refused")
        internal_error_response = Datadog::Core::Transport::InternalErrorResponse.new(connection_error)

        allow(mock_transport).to receive(:send_symbols).and_return(internal_error_response)

        expect(mock_transport).to receive(:send_symbols).once
        expect { uploader.upload_scopes([test_scope]) }.not_to raise_error
      end
    end

    context "with HTTP errors" do
      it "does not retry on 500 errors" do
        allow(mock_transport).to receive(:send_symbols)
          .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 500, internal_error?: false))

        expect(mock_transport).to receive(:send_symbols).once
        uploader.upload_scopes([test_scope])
      end

      it "does not retry on 429 rate limit" do
        allow(mock_transport).to receive(:send_symbols)
          .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 429, internal_error?: false))

        expect(mock_transport).to receive(:send_symbols).once
        uploader.upload_scopes([test_scope])
      end

      it "does not retry on 400 errors" do
        allow(mock_transport).to receive(:send_symbols)
          .and_return(instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 400, internal_error?: false))

        expect(logger).to receive(:debug) { |&block| expect(block.call).to match(/rejected/i) }

        uploader.upload_scopes([test_scope])
      end
    end
  end

  describe "event metadata structure" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    it "includes correct metadata fields" do
      # Capture the form passed to transport
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      # Read the event part
      event_io = captured_form["event"].instance_variable_get(:@io)
      event_json = JSON.parse(event_io.read)

      expect(event_json["ddsource"]).to eq("ruby")
      expect(event_json["service"]).to eq("test-service")
      expect(event_json["language"]).to eq("ruby")
      expect(event_json).to have_key("version")
      expect(event_json).to have_key("runtimeId")
      expect(event_json["type"]).to eq("symdb")
      expect(event_json).to have_key("uploadId")
      expect(event_json["batchNum"]).to eq(1)
      expect(event_json["final"]).to eq(false)
      expect(event_json["attachmentSize"]).to be > 0
    end
  end

  describe "upload metadata across batches" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    # Captures each event.json sent to the transport, in order.
    def capture_events
      captured = []
      allow(mock_transport).to receive(:send_symbols) do |form|
        event_io = form["event"].instance_variable_get(:@io)
        captured << JSON.parse(event_io.read)
        mock_response
      end
      yield
      captured
    end

    it "shares uploadId and increments batchNum across consecutive uploads" do
      events = capture_events do
        uploader.upload_scopes([test_scope])
        uploader.upload_scopes([Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Other")])
      end

      expect(events.size).to eq(2)
      expect(events[0]["uploadId"]).to eq(events[1]["uploadId"])
      expect(events[0]["batchNum"]).to eq(1)
      expect(events[1]["batchNum"]).to eq(2)
    end

    it "generates a UUID for uploadId" do
      events = capture_events { uploader.upload_scopes([test_scope]) }

      # SecureRandom.uuid format: 8-4-4-4-12 hex
      expect(events[0]["uploadId"]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "resets uploadId and batchNum when Process.pid changes (fork)" do
      # Stub Identity.id so that stubbing Process.pid below does not pollute
      # Datadog::Core::Environment::Identity module-level state. Identity uses
      # Process.pid to detect forks (Forking#forked?); calling Identity.id with
      # a stubbed pid runs its after_fork! block, setting @root_runtime_id and
      # @parent_runtime_id on the module — visible to later specs in the same
      # RSpec process (notably spec/datadog/core/environment/identity_spec.rb).
      allow(Datadog::Core::Environment::Identity).to receive(:id).and_return("test-runtime-id")

      events = capture_events do
        uploader.upload_scopes([test_scope])
        # Simulate fork: child observes a different Process.pid
        allow(Process).to receive(:pid).and_return(Process.pid + 1)
        uploader.upload_scopes([Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Other")])
      end

      expect(events.size).to eq(2)
      expect(events[0]["uploadId"]).not_to eq(events[1]["uploadId"])
      expect(events[0]["batchNum"]).to eq(1)
      expect(events[1]["batchNum"]).to eq(1)
    end

    it "embeds matching uploadId/batchNum in event and attachment for the same upload" do
      captured_event = nil
      captured_file = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_event = JSON.parse(form["event"].instance_variable_get(:@io).read)
        captured_file = JSON.parse(Zlib.gunzip(form["file"].instance_variable_get(:@io).read))
        mock_response
      end

      uploader.upload_scopes([test_scope])

      expect(captured_event["uploadId"]).to eq(captured_file["upload_id"])
      expect(captured_event["batchNum"]).to eq(captured_file["batch_num"])
      expect(captured_event["final"]).to eq(captured_file["final"])
      expect(captured_file["final"]).to eq(false)
    end

    it "sets attachmentSize to the gzipped attachment bytesize" do
      captured_event = nil
      captured_compressed_size = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_event = JSON.parse(form["event"].instance_variable_get(:@io).read)
        captured_compressed_size = form["file"].instance_variable_get(:@io).read.bytesize
        mock_response
      end

      uploader.upload_scopes([test_scope])

      expect(captured_event["attachmentSize"]).to eq(captured_compressed_size)
    end
  end

  describe "file part structure" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    it "creates compressed file with correct naming" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      file_upload = captured_form["file"]
      expect(file_upload.original_filename).to match(/symbols_\d+\.json\.gz/)
      expect(file_upload.content_type).to eq("application/gzip")
    end
  end

  # === Tests ported from Java BatchUploaderTest ===

  describe "multipart upload structure (ported from Java BatchUploaderTest.testUploadMultiPart)" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    it "event part contains ddsource, service, and type fields" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      event_io = captured_form["event"].instance_variable_get(:@io)
      event_json = JSON.parse(event_io.read)

      expect(event_json["ddsource"]).to eq("ruby")
      expect(event_json["service"]).to eq("test-service")
      expect(event_json["type"]).to eq("symdb")
    end

    it "file part is gzip compressed" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      file_upload = captured_form["file"]
      expect(file_upload.content_type).to eq("application/gzip")

      # Verify we can decompress and get valid JSON
      file_io = file_upload.instance_variable_get(:@io)
      compressed_data = file_io.read
      json_data = Zlib.gunzip(compressed_data)
      parsed = JSON.parse(json_data)

      expect(parsed["service"]).to eq("test-service")
      expect(parsed["language"]).to eq("ruby")
      expect(parsed["scopes"]).to be_an(Array)
    end
  end

  describe "upload with multiple scopes (ported from Java SymbolSinkTest.testMultiScopeFlush)" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    it "includes all scopes in a single upload" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      scopes = [
        Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Class1"),
        Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Class2"),
        Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Class3"),
      ]

      uploader.upload_scopes(scopes)

      file_upload = captured_form["file"]
      file_io = file_upload.instance_variable_get(:@io)
      compressed_data = file_io.read
      json_data = Zlib.gunzip(compressed_data)
      parsed = JSON.parse(json_data)

      scope_names = parsed["scopes"].map { |s| s["name"] }
      expect(scope_names).to include("Class1", "Class2", "Class3")
    end
  end

  # === Tests ported from Java BatchUploaderTest ===

  describe "multipart upload structure (ported from Java BatchUploaderTest.testUploadMultiPart)" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    it "event part contains ddsource, service, and type fields" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      event_io = captured_form["event"].instance_variable_get(:@io)
      event_json = JSON.parse(event_io.read)

      expect(event_json["ddsource"]).to eq("ruby")
      expect(event_json["service"]).to eq("test-service")
      expect(event_json["type"]).to eq("symdb")
    end

    it "file part is gzip compressed" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      uploader.upload_scopes([test_scope])

      file_upload = captured_form["file"]
      expect(file_upload.content_type).to eq("application/gzip")

      # Verify we can decompress and get valid JSON
      file_io = file_upload.instance_variable_get(:@io)
      compressed_data = file_io.read
      json_data = Zlib.gunzip(compressed_data)
      parsed = JSON.parse(json_data)

      expect(parsed["service"]).to eq("test-service")
      expect(parsed["language"]).to eq("ruby")
      expect(parsed["scopes"]).to be_an(Array)
    end
  end

  describe "upload with multiple scopes (ported from Java SymbolSinkTest.testMultiScopeFlush)" do
    before do
      allow(mock_transport).to receive(:send_symbols).and_return(mock_response)
    end

    it "includes all scopes in a single upload" do
      captured_form = nil
      allow(mock_transport).to receive(:send_symbols) do |form|
        captured_form = form
        mock_response
      end

      scopes = [
        Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Class1"),
        Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Class2"),
        Datadog::SymbolDatabase::Scope.new(scope_type: "CLASS", name: "Class3"),
      ]

      uploader.upload_scopes(scopes)

      file_upload = captured_form["file"]
      file_io = file_upload.instance_variable_get(:@io)
      compressed_data = file_io.read
      json_data = Zlib.gunzip(compressed_data)
      parsed = JSON.parse(json_data)

      scope_names = parsed["scopes"].map { |s| s["name"] }
      expect(scope_names).to include("Class1", "Class2", "Class3")
    end
  end

  describe "shutdown behavior (ported from Java BatchUploaderTest.testShutdown)" do
    it "handles nil scopes gracefully after construction" do
      expect(uploader.upload_scopes(nil)).to be_nil
    end

    it "handles empty scopes gracefully" do
      expect(uploader.upload_scopes([])).to be_nil
    end
  end
end
