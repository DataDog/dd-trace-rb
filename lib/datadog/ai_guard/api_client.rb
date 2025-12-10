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

      def initialize(endpoint:, api_key:, application_key:, timeout:)
        @api_key = api_key
        @application_key = application_key
        @timeout = timeout
        @site = Datadog.configuration.site || DEFAULT_SITE
        @endpoint = endpoint
      end

      def post(path:, request_body:)
        uri = URI::HTTPS.build(host: @site, path: @endpoint + path)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          request = Net::HTTP::Post.new(uri.request_uri, headers)
          request.body = request_body.to_json

          response = perform_request(request, http: http)

          parse_response_body(response.body)
        end
      end

      private

      def perform_request(request, http:)
        response = http.request(request)

        case response
        when Net::HTTPSuccess
          response
        when Net::HTTPRedirection
          raise UnexpectedRedirectError, "Redirects for AI Guard API are not supported"
        when Net::HTTPNotFound
          raise NotFoundError, response.body
        when Net::HTTPTooManyRequests
          raise TooManyRequestsError, response.body
        when Net::HTTPServerError
          raise ServerError, response.body
        when Net::HTTPClientError
          raise ClientError, response.body
        when Net::HTTPUnauthorized
          raise UnauthorizedError, response.body
        when Net::HTTPForbidden
          raise ForbiddenError, response.body
        else
          raise UnexpectedResponseError, response.body
        end
      end

      def parse_response_body(response_body)
        JSON.parse(response_body)
      rescue JSON::ParserError
        raise ResponseBodyParsingError, "Could not parse response body"
      end

      def headers
        {
          "DD-API-KEY": @api_key,
          "DD-APPLICATION-KEY": @application_key,
          "DD-AI-GUARD-VERSION": Datadog::VERSION::STRING,
          "DD-AI-GUARD-SOURCE": "SDK",
          "DD-AI-GUARD-LANGUAGE": "ruby",
          "content-type": "application/json"
        }
      end
    end
  end
end
