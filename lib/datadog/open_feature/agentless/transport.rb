# frozen_string_literal: true

require "net/http"
require "stringio"
require "timeout"
require "zlib"

require_relative "../../core/environment/identity"
require_relative "../../core/transport/ext"
require_relative "response"

module Datadog
  module OpenFeature
    module Agentless
      # HTTP transport for agentless configuration delivery.
      class Transport
        def initialize(endpoint:, api_key:, timeout_seconds:)
          @endpoint = endpoint
          @api_key = endpoint.managed? ? api_key : nil
          @timeout_seconds = timeout_seconds
        end

        def get(etag)
          request = Net::HTTP::Get.new(@endpoint.uri.request_uri, headers(etag))
          response = request(request)

          Response.new(
            status: response.code.to_i,
            etag: response["ETag"],
            body: response_body(response),
          )
        # Net::HTTP uses several version-specific exception types. None may end
        # the delivery worker; the poller classifies every transport failure.
        rescue => error
          Response.new(error: error)
        end

        private

        def headers(etag)
          headers = {
            "Accept-Encoding" => "gzip",
            "DD-Client-Library-Language" => Core::Environment::Identity.lang,
            "DD-Client-Library-Version" => Core::Environment::Identity.gem_datadog_version_semver2,
            Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST => "1",
          }
          headers["DD-API-KEY"] = @api_key if @api_key
          headers["If-None-Match"] = etag if etag
          headers
        end

        def request(request)
          uri = @endpoint.uri
          http = Net::HTTP.new(uri.host, uri.port, nil)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @timeout_seconds
          http.read_timeout = @timeout_seconds
          http.write_timeout = @timeout_seconds if http.respond_to?(:write_timeout=)

          Timeout.timeout(@timeout_seconds) do
            http.start { |connection| connection.request(request) }
          end
        end

        def response_body(response)
          body = response.body
          return body unless response["Content-Encoding"].to_s.strip.casecmp("gzip") == 0

          Zlib::GzipReader.new(StringIO.new(body)).read
        end
      end
    end
  end
end
