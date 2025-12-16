# frozen_string_literal: true

require "uri"
require "net/http"
require "json"

module Datadog
  module AIGuard
    # API Client for AI Guard API.
    # Uses net/http to perform request. Raises on client and server errors.
    class APIClient
      DEFAULT_SITE = "app.datadoghq.com"

      class UnexpectedRedirectError < StandardError; end

      class UnexpectedResponseError < StandardError; end

      class ResponseBodyParsingError < StandardError; end

      class ClientError < StandardError; end

      class NotFoundError < StandardError; end

      class TooManyRequestsError < ClientError; end

      class UnauthorizedError < ClientError; end

      class ForbiddenError < ClientError; end

      class ServerError < StandardError; end

      class ReadTimeout < StandardError; end

      def initialize(endpoint:, api_key:, application_key:, timeout:)
        @timeout = timeout
        @site = Datadog.configuration.site || DEFAULT_SITE
        @endpoint = endpoint

        @headers = {
          "DD-API-KEY": api_key.to_s,
          "DD-APPLICATION-KEY": application_key.to_s,
          "DD-AI-GUARD-VERSION": Datadog::VERSION::STRING,
          "DD-AI-GUARD-SOURCE": "SDK",
          "DD-AI-GUARD-LANGUAGE": "ruby",
          "content-type": "application/json"
        }.freeze
      end

      def post(path, body:)
        uri = URI::HTTPS.build(host: @site, path: @endpoint + path)

        Net::HTTP.start(uri.host.to_s, uri.port, use_ssl: true, read_timeout: @timeout) do |http|
          request = Net::HTTP::Post.new(uri.request_uri, @headers)
          request.body = body.to_json

          response = http.request(request)
          raise_on_http_error!(response)

          parse_response_body(response.body)
        end
      rescue Net::ReadTimeout
        raise ReadTimeout, "Request to AI Guard timed out"
      end

      private

      def raise_on_http_error!(response)
        case response
        when Net::HTTPSuccess
          # do nothing
        when Net::HTTPRedirection
          raise UnexpectedRedirectError, "Redirects for AI Guard API are not supported"
        when Net::HTTPNotFound
          raise NotFoundError, response.body
        when Net::HTTPTooManyRequests
          raise TooManyRequestsError, response.body
        when Net::HTTPServerError
          raise ServerError, response.body
        when Net::HTTPUnauthorized
          raise UnauthorizedError, response.body
        when Net::HTTPForbidden
          raise ForbiddenError, response.body
        when Net::HTTPClientError
          raise ClientError, response.body
        else
          raise UnexpectedResponseError, response.body
        end
      end

      def parse_response_body(body)
        JSON.parse(body)
      rescue JSON::ParserError
        raise ResponseBodyParsingError, "Could not parse response body"
      end
    end
  end
end
