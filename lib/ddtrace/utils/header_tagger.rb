module Datadog
  module Utils
    # Helper class to used to tag configured headers
    class HeaderTagger
      DEFAULT_HEADERS = {
        response: %w[Content-Type X-Request-ID]
      }.freeze

      attr_reader :configuration

      def initialize(configuration)
        @configuration = configuration
      end

      def tag_headers(request_span, env, response_headers)
        # Request headers
        parse_request_headers(env).each do |name, value|
          request_span.set_tag(name, value) if request_span.get_tag(name).nil?
        end

        # Response headers
        parse_response_headers(response_headers || {}).each do |name, value|
          request_span.set_tag(name, value) if request_span.get_tag(name).nil?
        end
      end

      private

      def parse_request_headers(env)
        whitelist = configuration[:headers][:request] || []
        whitelist.each_with_object({}) do |header, result|
          header_value = request_header(env, header)
          result[Datadog::Ext::HTTP::RequestHeaders.to_tag(header)] = header_value if header_value
        end
      end

      def parse_response_headers(headers)
        whitelist = configuration[:headers][:response] || []
        whitelist.each_with_object({}) do |header, result|
          if headers.key?(header)
            result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[header]
          else
            # Try a case-insensitive lookup
            uppercased_header = header.to_s.upcase
            matching_header = headers.keys.find {|h| h.upcase == uppercased_header}
            if matching_header
              result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[matching_header]
            end
          end
        end
      end

      def request_header(env, header)
        env[header_to_rack_header(header)]
      end

      def header_to_rack_header(name)
        "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
      end
    end
  end
end
