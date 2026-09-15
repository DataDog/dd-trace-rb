# frozen_string_literal: true

require "net/http"
require "stringio"
require "timeout"
require "uri"
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
          apply_custom_authentication(request)
          response = request(request)
          status = response.code.to_i

          Response.new(
            status: status,
            etag: response["ETag"],
            # Decoding another status can erase the status the poller needs to classify the response.
            body: (status == 200) ? response_body(response) : nil,
          )
        # Net::HTTP uses several version-specific exception types. None may end
        # the delivery worker; the poller classifies every transport failure.
        rescue => error
          Response.new(error: error)
        end

        private

        def apply_custom_authentication(request)
          return if @endpoint.managed?

          uri = @endpoint.uri
          username = uri.user
          return unless username

          request.basic_auth(
            URI::RFC2396_PARSER.unescape(username),
            URI::RFC2396_PARSER.unescape(uri.password.to_s),
          )
        end

        def headers(etag)
          headers = {
            "Accept-Encoding" => "gzip",
            "DD-Client-Library-Language" => Core::Environment::Identity.lang,
            "DD-Client-Library-Version" => Core::Environment::Identity.gem_datadog_version_semver2,
            Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST => "1",
          }
          api_key = @api_key
          headers[Core::Transport::Ext::HTTP::HEADER_DD_API_KEY] = api_key if api_key
          headers["If-None-Match"] = etag if etag
          headers
        end

        def request(request)
          uri = @endpoint.uri
          hostname = uri.hostname
          raise ArgumentError, "Feature Flags agentless endpoint must have a host" unless hostname

          # Agentless delivery requires public egress, so use Ruby's standard proxy discovery.
          http = Net::HTTP.new(hostname, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @timeout_seconds
          http.read_timeout = @timeout_seconds
          http.write_timeout = @timeout_seconds if http.respond_to?(:write_timeout=)

          Timeout.timeout(@timeout_seconds) do
            http.start { |connection| connection.request(request) }
          end
        end

        def response_body(response)
          body = response.body.to_s
          return body unless response["Content-Encoding"].to_s.strip.casecmp("gzip") == 0

          reader = Zlib::GzipReader.new(StringIO.new(body))
          begin
            reader.read.to_s
          ensure
            reader.close
          end
        end
      end
    end
  end
end
