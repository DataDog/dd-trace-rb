# frozen_string_literal: true

require 'net/http'
require 'uri'

require_relative '../../../core/transport/ext'

module Datadog
  module Tracing
    module Transport
      module OTLP
        # Sends an already-encoded OTLP http/json payload to the configured OTLP traces endpoint
        # via an HTTP POST. The endpoint is independent of the Datadog agent URL and is used as-is.
        #
        # Hand-rolled with Net::HTTP, mirroring dd-trace-js's pure exporter, to avoid pulling in the
        # heavy `opentelemetry-exporter-otlp` gem on the trace path.
        class Exporter
          CONTENT_TYPE = 'application/json'

          attr_reader :uri, :headers, :timeout_seconds, :logger

          # @param endpoint [String] full OTLP traces endpoint URL
          # @param headers [Hash<String,String>,nil] extra request headers
          # @param timeout_millis [Integer] request timeout in milliseconds
          # @param logger [Datadog::Core::Logger]
          def initialize(endpoint:, headers:, timeout_millis:, logger:)
            @uri = URI(endpoint)
            @headers = headers || {}
            @timeout_seconds = timeout_millis / 1000.0
            @logger = logger
          end

          # Sends a single encoded payload.
          #
          # @param payload [String] OTLP http/json request body
          # @return [Boolean] `true` on a 2xx response, `false` otherwise (errors are logged, not raised)
          def export(payload)
            http = Net::HTTP.new(uri.host, uri.port) # steep:ignore ArgumentTypeMismatch
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = timeout_seconds
            http.read_timeout = timeout_seconds
            http.write_timeout = timeout_seconds if http.respond_to?(:write_timeout=)

            request = Net::HTTP::Post.new(request_path)
            request['Content-Type'] = CONTENT_TYPE
            # Prevent the gem's own Net::HTTP instrumentation from tracing this export request.
            request[Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = '1'
            headers.each { |key, value| request[key] = value }
            request.body = payload

            response = http.request(request)
            success = response.is_a?(Net::HTTPSuccess)
            unless success
              logger.debug { "OTLP trace export failed: HTTP #{response.code} #{response.body}" }
            end
            success
          rescue => e
            logger.debug { "OTLP trace export error: #{e.class}: #{e.message}" }
            false
          end

          private

          def request_path
            path = uri.path
            path = '/' if path.nil? || path.empty?
            query = uri.query
            query ? "#{path}?#{query}" : path
          end
        end
      end
    end
  end
end
