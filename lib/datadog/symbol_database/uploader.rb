# frozen_string_literal: true

require 'json'
require 'zlib'
require 'net/http'
require 'stringio'
require_relative '../core/vendor/multipart-post/net/http/post/multipart'
require_relative '../core/vendor/multipart-post/multipart/post/composite_read_io'
require_relative 'service_version'

module Datadog
  module SymbolDatabase
    # Uploads symbol database payloads to the Datadog agent via HTTP multipart.
    #
    # Handles the complete upload process:
    # 1. Wraps scopes in ServiceVersion (adds service/env/version metadata)
    # 2. Serializes to JSON
    # 3. Compresses with GZIP (always, ~40:1 ratio expected)
    # 4. Builds multipart form: event.json (metadata) + symbols_{pid}.json.gz (data)
    # 5. POSTs to agent at /symdb/v1/input
    # 6. Retries up to 10 times with exponential backoff on failures
    #
    # Uses vendored multipart-post library for form-data construction.
    # Headers: DD-API-KEY, Datadog-Container-ID, Datadog-Entity-ID (from Core::Environment::Container)
    #
    # Called by: ScopeContext.perform_upload (when batch ready)
    # Calls: Net::HTTP for transport, Zlib for compression
    # Tracks: Telemetry metrics for uploads, errors, payload sizes
    class Uploader
      MAX_PAYLOAD_SIZE = 50 * 1024 * 1024  # 50MB
      MAX_RETRIES = 10
      BASE_BACKOFF = 0.1  # 100ms
      MAX_BACKOFF = 30.0  # 30 seconds

      def initialize(config, telemetry: nil)
        @config = config
        @telemetry = telemetry
      end

      # Upload a batch of scopes
      # @param scopes [Array<Scope>] Scopes to upload
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
        # Don't propagate
      end

      private

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
        nil
      end

      def compress_payload(json_data)
        compressed = Zlib.gzip(json_data)
        # Track compression ratio
        ratio = json_data.bytesize.to_f / compressed.bytesize
        @telemetry&.distribution('symbol_database.compression_ratio', ratio)
        compressed
      rescue => e
        Datadog.logger.debug("SymDB: Compression failed: #{e.class}: #{e}")
        @telemetry&.count('symbol_database.compression_error', 1)
        nil
      end

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
          end
        end
      end

      def calculate_backoff(retry_count)
        backoff = BASE_BACKOFF * (2**(retry_count - 1))
        backoff = [backoff, MAX_BACKOFF].min
        backoff * (0.5 + rand * 0.5)  # Add jitter
      end

      def perform_http_upload(compressed_data, scope_count)
        # Track payload size
        @telemetry&.distribution('symbol_database.payload_size', compressed_data.bytesize)

        uri = URI.parse(agent_url)

        # Build multipart form
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

        form_data = {
          'event' => event_upload,
          'file' => file_upload
        }

        # Create multipart request
        request = Datadog::Core::Vendor::Net::HTTP::Post::Multipart.new(
          '/symdb/v1/input',
          form_data,
          build_headers
        )

        # Send request
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = upload_timeout
        http.open_timeout = upload_timeout

        response = http.request(request)

        handle_response(response, scope_count)
      end

      def build_event_metadata
        JSON.generate(
          ddsource: 'ruby',
          service: @config.service,
          runtimeId: Datadog::Core::Environment::Identity.id,
          parentId: nil,  # Fork tracking deferred for MVP
          type: 'symdb'
        )
      end

      def build_headers
        headers = {}

        # API key
        headers['DD-API-KEY'] = @config.api_key if @config.api_key

        # Container headers
        headers.merge!(Datadog::Core::Environment::Container.to_headers)

        headers
      end

      def agent_url
        # Get agent URL from configuration
        # For now, construct from agent host/port
        host = @config.agent&.host || '127.0.0.1'
        port = @config.agent&.port || 8126
        "http://#{host}:#{port}"
      end

      def upload_timeout
        @config.agent&.timeout_seconds || 30
      end

      def handle_response(response, scope_count)
        case response.code.to_i
        when 200..299
          Datadog.logger.debug("SymDB: Uploaded #{scope_count} scopes successfully")
          @telemetry&.count('symbol_database.uploaded', 1)
          @telemetry&.count('symbol_database.scopes_uploaded', scope_count)
          true
        when 429
          @telemetry&.count('symbol_database.upload_error', 1, tags: ['error:rate_limited'])
          raise "Rate limited"
        when 500..599
          @telemetry&.count('symbol_database.upload_error', 1, tags: ['error:server_error'])
          raise "Server error: #{response.code}"
        else
          @telemetry&.count('symbol_database.upload_error', 1, tags: ['error:client_error'])
          Datadog.logger.debug("SymDB: Upload rejected: #{response.code}")
          false
        end
      end
    end
  end
end
