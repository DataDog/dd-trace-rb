# frozen_string_literal: true

require 'json'
require 'net/http'
require 'zlib'
require 'stringio'
require 'uri'
require 'cgi'
require_relative '../core/vendor/multipart-post/net/http/post/multipart'

module Datadog
  module SymbolDatabase
    # Uploads symbol data to the Datadog agent via multipart HTTP POST.
    #
    # @api private
    class Uploader
      MAX_RETRIES = 10
      UPLOAD_TIMEOUT = 30

      # Raised for HTTP errors that should be retried
      class RetryableError < StandardError; end

      def initialize(settings, agent_settings, logger)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
      end

      def upload_with_retry(json_payload)
        retries = 0
        begin
          upload(json_payload)
        rescue RetryableError, Net::OpenTimeout, Net::ReadTimeout,
               Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE => e
          retries += 1
          if retries <= MAX_RETRIES
            @logger.debug { "symbol_database: upload retry #{retries}/#{MAX_RETRIES}: #{e.class}: #{e}" }
            sleep(retry_delay(retries))
            retry
          end
          @logger.debug { "symbol_database: upload failed after #{retries} attempts: #{e.class}: #{e}" }
        rescue => e
          @logger.debug { "symbol_database: upload failed: #{e.class}: #{e}" }
        end
      end

      private

      def upload(json_payload)
        compressed = Zlib.gzip(json_payload)

        event_json = JSON.generate({
          ddsource: 'dd_debugger',
          service: @settings.service,
          runtimeId: Core::Environment::Identity.id,
          type: 'symdb',
        })

        event_io = Core::Vendor::Multipart::Post::UploadIO.new(
          StringIO.new(event_json), 'application/json', 'event.json'
        )
        file_io = Core::Vendor::Multipart::Post::UploadIO.new(
          StringIO.new(compressed), 'application/gzip', "symbols_#{Process.pid}.json.gz"
        )

        uri = build_uri
        req = Core::Vendor::Net::HTTP::Post::Multipart.new(
          uri.request_uri,
          { 'event' => event_io, 'file' => file_io },
          build_headers,
        )

        response = ::Net::HTTP.start(uri.host, uri.port) do |http|
          http.open_timeout = UPLOAD_TIMEOUT
          http.read_timeout = UPLOAD_TIMEOUT
          http.request(req)
        end

        handle_response(response)
      end

      def build_uri
        host = @agent_settings.hostname
        port = @agent_settings.port
        path = '/symdb/v1/input'

        tags = build_ddtags
        query = tags && !tags.empty? ? "ddtags=#{CGI.escape(tags)}" : nil

        URI::HTTP.build(host: host, port: port, path: path, query: query)
      end

      def build_headers
        headers = {}
        headers.merge!(Core::Environment::Container.to_headers)
        headers
      end

      def build_ddtags
        tags = []
        tags << "env:#{@settings.env}" if @settings.env
        tags << "version:#{@settings.version}" if @settings.version
        tags << "host:#{Core::Environment::Identity.hostname}" if Core::Environment::Identity.respond_to?(:hostname)
        tags.join(',')
      rescue
        nil
      end

      def handle_response(response)
        case response.code.to_i
        when 200..299
          @logger.debug { 'symbol_database: upload successful' }
        when 408, 429
          raise RetryableError, "HTTP #{response.code}"
        when 500..599
          raise RetryableError, "HTTP #{response.code}"
        else
          @logger.debug { "symbol_database: upload failed with HTTP #{response.code}, not retrying" }
        end
      end

      def retry_delay(attempt)
        base = 0.1
        max_delay = 30.0
        delay = [base * (2**attempt), max_delay].min
        delay + rand * delay * 0.1
      end
    end
  end
end
