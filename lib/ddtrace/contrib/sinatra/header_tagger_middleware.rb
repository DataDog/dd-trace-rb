require 'ddtrace/contrib/sinatra/request_span'

module Datadog
  module Contrib
    module Sinatra
      # Middleware used for automatically tagging configured headers and handle request span
      class HeaderTaggerMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          span = RequestSpan.span!(env)

          # Request headers
          parse_request_headers(env).each do |name, value|
            span.set_tag(name, value) if span.get_tag(name).nil?
          end

          status, headers, response_body = @app.call(env)

          # Response headers
          parse_response_headers(headers).each do |name, value|
            span.set_tag(name, value) if span.get_tag(name).nil?
          end

          [status, headers, response_body]
        end

        private

        def parse_request_headers(env)
          {}.tap do |result|
            whitelist = configuration[:headers][:request] || []
            whitelist.each do |header|
              rack_header = header_to_rack_header(header)
              if env.key?(rack_header)
                result[Datadog::Ext::HTTP::RequestHeaders.to_tag(header)] = env[rack_header]
              end
            end
          end
        end

        def parse_response_headers(headers)
          {}.tap do |result|
            whitelist = configuration[:headers][:response] || []
            whitelist.each do |header|
              if headers.key?(header)
                result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[header]
              else
                # Try a case-insensitive lookup
                uppercased_header = header.to_s.upcase
                matching_header = headers.keys.find { |h| h.upcase == uppercased_header }
                if matching_header
                  result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[matching_header]
                end
              end
            end
          end
        end

        def configuration
          Datadog.configuration[:sinatra]
        end

        def header_to_rack_header(name)
          "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
        end
      end
    end
  end
end
