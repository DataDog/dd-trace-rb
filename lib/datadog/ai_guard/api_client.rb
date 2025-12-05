# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'

module Datadog
  module AIGuard
    # API Client for AI Guard API
    class APIClient
      DEFAULT_SITE = 'app.datadoghq.com'

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

          # TODO: handle http errors?
          response = http.request(request)

          # TODO: handle JSON parsing errors?
          JSON.parse(response.body)
        end
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
