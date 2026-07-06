# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'zlib'
require 'stringio'
require_relative '../core/environment/identity'
require_relative '../core/vendor/multipart-post/multipart/post/composite_read_io'
require_relative '../tracing/ext'
require_relative 'service_version'
require_relative 'transport/http'
require_relative '../di/fatal_exceptions'

module Datadog
  module SymbolDatabase
    # Uploads symbol database payloads to the Datadog agent via HTTP multipart.
    #
    # Handles the complete upload process:
    # 1. Wraps scopes in ServiceVersion (adds service/env/version metadata)
    # 2. Serializes to JSON
    # 3. Compresses with GZIP (always, ~40:1 ratio expected)
    # 4. Builds multipart form: event.json (metadata) + symbols_{pid}.json.gz (data)
    # 5. POSTs to agent at /symdb/v1/input via Core::Transport::HTTP
    # No retries — single attempt. Any failure is logged at debug and discarded.
    #
    # Uses Core::Transport::HTTP infrastructure (consistent with DI, Profiling, DataStreams).
    # Headers: DD-API-KEY, Datadog-Container-ID, Datadog-Entity-ID (automatic from transport)
    #
    # Called by: ScopeBatcher.perform_upload (when batch ready)
    # Calls: Transport::HTTP for network, Zlib for compression
    #
    # @api private
    class Uploader
      MAX_PAYLOAD_SIZE = 50 * 1024 * 1024  # 50MB

      # Initialize uploader.
      # @param settings [Configuration::Settings] Tracer settings (for service, env, version metadata)
      # @param agent_settings [Configuration::AgentSettings] Agent connection settings
      # @param logger [Logger] Logger instance
      # @param telemetry [Telemetry, nil] Optional telemetry component for error reporting
      def initialize(settings:, agent_settings:, logger:, telemetry: nil)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
        @telemetry = telemetry

        @transport = Transport::HTTP.symbols(
          agent_settings: agent_settings,
          logger: @logger,
        )

        # Protects the lazy initialization of @upload_pid/@upload_id and the
        # @batch_num increment in next_upload_metadata. ScopeBatcher calls
        # upload_scopes outside its own mutex, so two threads (e.g. a size-
        # triggered flush and the timer/shutdown path) can race here.
        @metadata_mutex = Mutex.new
      end

      # Upload a batch of scopes to the agent.
      # Wraps in ServiceVersion, serializes to JSON, compresses with GZIP,
      # builds multipart form, and POSTs to /symdb/v1/input via transport.
      # No retries — single attempt, matching Python behavior.
      # @param scopes [Array<Scope>] Scopes to upload
      # @return [void]
      def upload_scopes(scopes)
        return if scopes.empty?

        upload_id, batch_num = next_upload_metadata
        json_data = build_symbol_payload(scopes, upload_id: upload_id, batch_num: batch_num)
        compressed_data = Zlib.gzip(json_data)

        # Emitted unconditionally so the rare oversized case is observable.
        @telemetry&.distribution(
          Tracing::Ext::TELEMETRY_METRICS_NAMESPACE,
          'symbol_database.payload_size',
          compressed_data.bytesize
        )

        # Symbols for very large applications (>50MB after gzip) are dropped:
        # the upload is skipped and the customer sees no autocomplete /
        # symbol probe results for those classes. Java handles the same case
        # by splitting the payload across multiple requests; we have not
        # implemented splitting here. Deferred for a post-MVP follow-up.
        if compressed_data.bytesize > MAX_PAYLOAD_SIZE
          @logger.debug { "symdb: payload too large: #{compressed_data.bytesize}/#{MAX_PAYLOAD_SIZE} bytes, skipping" }
          return
        end

        perform_http_upload(compressed_data, scopes.size, upload_id: upload_id, batch_num: batch_num)
      rescue Exception => e # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(e)
        @logger.debug { "symdb: upload failed: #{e.class}: #{e.message}" }
        @telemetry&.report(e, description: 'symdb: upload failed')
      end

      private

      # Build JSON payload from scopes.
      # @param scopes [Array<Scope>] Scopes to serialize
      # @param upload_id [String] UUID identifying the logical upload
      # @param batch_num [Integer] 1-indexed batch number within the upload
      # @return [String] JSON string
      def build_symbol_payload(scopes, upload_id:, batch_num:)
        ServiceVersion.new(
          service: @settings.service,
          env: @settings.env,
          version: @settings.version,
          scopes: scopes,
          upload_id: upload_id,
          batch_num: batch_num,
          # Always false: the Ruby tracer continuously uploads new code
          # as files are loaded; there is no defined end-of-upload point.
          final: false,
        ).to_json
      end

      # Perform HTTP POST with multipart form-data via transport layer.
      # @param compressed_data [String] GZIP compressed JSON payload
      # @param scope_count [Integer] Number of scopes (for logging)
      # @param upload_id [String] UUID identifying the logical upload
      # @param batch_num [Integer] 1-indexed batch number within the upload
      # @return [void]
      def perform_http_upload(compressed_data, scope_count, upload_id:, batch_num:)
        form = build_multipart_form(compressed_data, upload_id: upload_id, batch_num: batch_num)
        response = @transport.send_symbols(form)
        handle_response(response, scope_count)
      end

      # Build multipart form-data with event metadata and compressed symbols.
      # @param compressed_data [String] GZIP compressed JSON payload
      # @param upload_id [String] UUID identifying the logical upload
      # @param batch_num [Integer] 1-indexed batch number within the upload
      # @return [Hash] Form data hash with UploadIO objects
      def build_multipart_form(compressed_data, upload_id:, batch_num:)
        event_io = StringIO.new(
          build_event_metadata(compressed_data.bytesize, upload_id: upload_id, batch_num: batch_num),
        )
        file_io = StringIO.new(compressed_data)

        event_upload = Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
          event_io,
          'application/json',
          'event.json',
        )

        file_upload = Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
          file_io,
          'application/gzip',
          "symbols_#{Process.pid}.json.gz",
        )

        {
          'event' => event_upload,
          'file' => file_upload,
        }
      end

      # Build event.json metadata part.
      # @param attachment_size [Integer] Size of the compressed attachment in bytes
      # @param upload_id [String] UUID identifying the logical upload
      # @param batch_num [Integer] 1-indexed batch number within the upload
      # @return [String] JSON string for event metadata
      def build_event_metadata(attachment_size, upload_id:, batch_num:)
        JSON.generate(
          ddsource: 'ruby',
          service: @settings.service,
          version: @settings.version,
          language: 'ruby',
          runtimeId: Datadog::Core::Environment::Identity.id,
          parentId: nil,  # Fork tracking deferred for MVP
          type: 'symdb',
          uploadId: upload_id,
          batchNum: batch_num,
          # Always false: the Ruby tracer continuously uploads new code
          # as files are loaded; there is no defined end-of-upload point.
          final: false,
          attachmentSize: attachment_size,
        )
      end

      # Return [upload_id, batch_num] for the current process. upload_id is
      # generated lazily on first use and shared by all batches uploaded from
      # the process. A forked child observes a different Process.pid and
      # therefore gets a fresh upload_id and batch counter.
      # Synchronized: ScopeBatcher releases its mutex before calling
      # upload_scopes, so this can be entered concurrently.
      # @return [Array<(String, Integer)>]
      def next_upload_metadata
        @metadata_mutex.synchronize do
          if @upload_pid != Process.pid
            @upload_pid = Process.pid
            @upload_id = SecureRandom.uuid.freeze
            @batch_num = 0
          end
          @batch_num += 1 # steep:ignore NoMethod
          # @upload_id and @batch_num are non-nil after the branch above; refine for Steep.
          upload_id = @upload_id or raise('unreachable: @upload_id should be set')
          batch_num = @batch_num or raise('unreachable: @batch_num should be set')
          [upload_id, batch_num]
        end
      end

      # Handle HTTP response and track metrics.
      # @param response [Core::Transport::Response] HTTP response from agent
      # @param scope_count [Integer] Number of scopes uploaded
      # @return [Boolean] true if successful, false otherwise
      def handle_response(response, scope_count)
        if response.internal_error?
          @logger.debug { "symdb: upload failed: #{response.error.class}: #{response.error}" } # steep:ignore NoMethod
          return false
        end

        case response.code
        when 200..299
          @logger.debug { "symdb: uploaded #{scope_count} scopes successfully" }
          true
        when 429
          @logger.debug { "symdb: upload rejected: rate limited (429)" }
          false
        when 500..599
          @logger.debug { "symdb: upload rejected: server error (#{response.code})" }
          false
        else
          @logger.debug { "symdb: upload rejected: #{response.code}" }
          false
        end
      end
    end
  end
end
