# frozen_string_literal: true

# TODO: Revert ddsource to 'ruby' after DataDog/debugger-backend#1974 merges.
# See service_version.rb for full revert instructions.

require 'json'
require 'zlib'
require 'stringio'
require_relative '../core/vendor/multipart-post/multipart/post/composite_read_io'
require_relative 'service_version'
require_relative 'transport/http'

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
    # 6. Retries handled by transport layer
    #
    # Uses Core::Transport::HTTP infrastructure (consistent with DI, Profiling, DataStreams).
    # Headers: DD-API-KEY, Datadog-Container-ID, Datadog-Entity-ID (automatic from transport)
    #
    # Called by: ScopeContext.perform_upload (when batch ready)
    # Calls: Transport::HTTP for network, Zlib for compression
    # Tracks: Telemetry metrics for uploads, errors, payload sizes
    #
    # @api private
    class Uploader
      MAX_PAYLOAD_SIZE = 50 * 1024 * 1024  # 50MB
      MAX_RETRIES = 10
      BASE_BACKOFF_INTERVAL = 0.1  # 100ms
      MAX_BACKOFF_INTERVAL = 30.0  # 30 seconds

      # Initialize uploader.
      # @param config [Configuration] Tracer configuration (for service, env, version metadata)
      # @param agent_settings [Configuration::AgentSettings] Agent connection settings
      # @param telemetry [Telemetry, nil] Optional telemetry for metrics
      def initialize(config, agent_settings, telemetry: nil)
        @config = config
        @agent_settings = agent_settings
        @telemetry = telemetry

        # Initialize transport using symbol database transport infrastructure
        @transport = Transport::HTTP.build(
          agent_settings: agent_settings,
          logger: Datadog.logger
        )
      end

      # Upload a batch of scopes to the agent.
      # Wraps in ServiceVersion, serializes to JSON, compresses with GZIP,
      # builds multipart form, and POSTs to /symdb/v1/input via transport.
      # Retries handled by this layer (transport doesn't retry by default).
      # @param scopes [Array<Scope>] Scopes to upload
      # @return [void]
      def upload_scopes(scopes)
        return if scopes.nil? || scopes.empty?

        # Build and serialize payload
        json_data = build_symbol_payload(scopes)
        return unless json_data

        # Compress
        compressed_data = compress_payload(json_data)
        return unless compressed_data

        # Check size
        if compressed_data.bytesize > MAX_PAYLOAD_SIZE
          Datadog.logger.debug(
            "SymDB: Payload too large: #{compressed_data.bytesize}/#{MAX_PAYLOAD_SIZE} bytes, skipping"
          )
          return
        end

        # Upload with retry
        upload_with_retry(compressed_data, scopes.size)
      rescue => e
        Datadog.logger.debug("SymDB: Upload failed: #{e.class}: #{e}")
        @telemetry&.inc('tracers', 'symbol_database.upload_scopes_error', 1)
        # Don't propagate
      end

      # @api private
      private

      # Build JSON payload from scopes.
      # @param scopes [Array<Scope>] Scopes to serialize
      # @return [String, nil] JSON string or nil if serialization fails
      def build_symbol_payload(scopes)
        service_version = ServiceVersion.new(
          service: @config.service,
          env: @config.env,
          version: @config.version,
          scopes: scopes
        )

        service_version.to_json
      rescue => e
        Datadog.logger.debug("SymDB: Serialization failed: #{e.class}: #{e}")
        @telemetry&.inc('tracers', 'symbol_database.serialization_error', 1)
        nil
      end

      # Compress JSON with GZIP.
      # @param json_data [String] JSON string to compress
      # @return [String, nil] GZIP compressed data or nil if compression fails
      def compress_payload(json_data)
        compressed = Zlib.gzip(json_data)
        # Track compression ratio
        ratio = json_data.bytesize.to_f / compressed.bytesize
        @telemetry&.distribution('tracers', 'symbol_database.compression_ratio', ratio)
        compressed
      rescue => e
        Datadog.logger.debug("SymDB: Compression failed: #{e.class}: #{e}")
        @telemetry&.inc('tracers', 'symbol_database.compression_error', 1)
        nil
      end

      # Upload with retry logic (up to 10 retries with exponential backoff).
      # @param compressed_data [String] GZIP compressed payload
      # @param scope_count [Integer] Number of scopes being uploaded
      # @return [void]
      def upload_with_retry(compressed_data, scope_count)
        retries = 0

        begin
          perform_http_upload(compressed_data, scope_count)
        rescue => e
          retries += 1

          if retries <= MAX_RETRIES
            backoff = calculate_backoff(retries)
            Datadog.logger.debug(
              "SymDB: Upload failed (#{retries}/#{MAX_RETRIES}), retrying in #{backoff}s: #{e.class}: #{e}"
            )
            sleep(backoff)
            retry
          else
            Datadog.logger.debug("SymDB: Upload failed after #{MAX_RETRIES} retries: #{e.class}: #{e}")
            @telemetry&.inc('tracers', 'symbol_database.upload_retry_exhausted', 1)
          end
        end
      end

      # Calculate exponential backoff with jitter.
      # @param retry_count [Integer] Current retry attempt number
      # @return [Float] Backoff duration in seconds
      def calculate_backoff(retry_count)
        backoff = BASE_BACKOFF_INTERVAL * (2**(retry_count - 1))
        backoff = [backoff, MAX_BACKOFF_INTERVAL].min
        backoff * (0.5 + rand * 0.5)  # Add jitter
      end

      # Perform HTTP POST with multipart form-data via transport layer.
      # @param compressed_data [String] GZIP compressed JSON payload
      # @param scope_count [Integer] Number of scopes (for logging)
      # @return [void]
      def perform_http_upload(compressed_data, scope_count)
        # Track payload size
        @telemetry&.distribution('tracers', 'symbol_database.payload_size', compressed_data.bytesize)

        # Build multipart form
        form = build_multipart_form(compressed_data)

        # Send via transport (uses Core::Transport::HTTP infrastructure)
        response = @transport.send_symdb_payload(form)

        handle_response(response, scope_count)
      end

      # Build multipart form-data with event metadata and compressed symbols.
      # @param compressed_data [String] GZIP compressed JSON payload
      # @return [Hash] Form data hash with UploadIO objects
      def build_multipart_form(compressed_data)
        event_io = StringIO.new(build_event_metadata)
        file_io = StringIO.new(compressed_data)

        event_upload = Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
          event_io,
          'application/json',
          'event.json'
        )

        file_upload = Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
          file_io,
          'application/gzip',
          "symbols_#{Process.pid}.json.gz"
        )

        {
          'event' => event_upload,
          'file' => file_upload
        }
      end

      # Build event.json metadata part.
      # @return [String] JSON string for event metadata
      def build_event_metadata
        JSON.generate(
          ddsource: 'dd_debugger', # TEMPORARY: revert to 'ruby' after debugger-backend#1974
          service: @config.service,
          runtimeId: Datadog::Core::Environment::Identity.id,
          parentId: nil,  # Fork tracking deferred for MVP
          type: 'symdb'
        )
      end

      # Handle HTTP response and track metrics.
      # @param response [Core::Transport::Response] HTTP response from agent
      # @param scope_count [Integer] Number of scopes uploaded
      # @return [Boolean] true if successful, false otherwise
      def handle_response(response, scope_count)
        case response.code
        when 200..299
          Datadog.logger.debug("SymDB: Uploaded #{scope_count} scopes successfully")
          @telemetry&.inc('tracers', 'symbol_database.uploaded', 1)
          @telemetry&.inc('tracers', 'symbol_database.scopes_uploaded', scope_count)
          true
        when 429
          @telemetry&.inc('tracers', 'symbol_database.upload_error', 1, tags: ['error:rate_limited'])
          # Raise to trigger retry logic in upload_with_retry (line 130-144).
          # This follows the same pattern as Core::Transport - retryable errors raise,
          # non-retryable errors return false. Agent rate limiting is transient and retryable.
          raise "Rate limited"
        when 500..599
          @telemetry&.inc('tracers', 'symbol_database.upload_error', 1, tags: ['error:server_error'])
          # Raise to trigger retry logic in upload_with_retry (line 130-144).
          # Server errors (500-599) are transient and retryable with exponential backoff.
          raise "Server error: #{response.code}"
        else
          @telemetry&.inc('tracers', 'symbol_database.upload_error', 1, tags: ['error:client_error'])
          Datadog.logger.debug("SymDB: Upload rejected: #{response.code}")
          false
        end
      end
    end
  end
end
