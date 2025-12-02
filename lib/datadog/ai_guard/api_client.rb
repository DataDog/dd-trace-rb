# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'

module Datadog
  module AIGuard
    # API Client for AI Guard API
    class APIClient
      def initialize(endpoint:, api_key:, application_key:, timeout:)
        @api_key = api_key
        @application_key = application_key
        @timeout = timeout
        @endpoint = endpoint

        endpoint_uri = URI.parse(@endpoint)
        @http = Net::HTTP.new(endpoint_uri.host, endpoint_uri.port)
        @http.use_ssl = true
      end

      def post(path:, request_body:)
        uri = URI.parse(@endpoint)
        uri.path += path

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = request_body.to_json

        # TODO: handle http errors
        response = @http.request(request)

        # TODO: handle json parsing errors
        JSON.parse(response.body)
      end

      private

      def headers
        {
          'DD-API-KEY': @api_key,
          'DD-APPLICATION-KEY': @application_key,
          'DD-AI-GUARD-VERSION': Datadog::VERSION::STRING,
          'DD-AI-GUARD-SOURCE': 'SDK',
          'DD-AI-GUARD-LANGUAGE': 'ruby',
          'content-type': 'application/json'
        }
      end
    end
  end
end
