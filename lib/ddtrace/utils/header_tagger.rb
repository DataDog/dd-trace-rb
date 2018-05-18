module Datadog
  module Utils
    # Helper class to used to tag configured headers
    module HeaderTagger
      DEFAULT_HEADERS = {
        response: %w[Content-Type X-Request-ID]
      }.freeze

      # Tag headers from Rack requests
      module RackRequest
        module_function

        def name(header)
          Datadog::Ext::HTTP::RequestHeaders.to_tag(header)
        end

        def value(header, env)
          rack_header = "HTTP_#{header.to_s.upcase.gsub(/[-\s]/, '_')}"

          env[rack_header]
        end
      end

      # Tag headers from Rack responses
      module RackResponse
        module_function

        def name(header)
          Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)
        end

        def value(header, headers)
          return if headers.nil?

          if headers.key?(header)
            headers[header]
          else
            # Try a case-insensitive lookup
            uppercased_header = header.to_s.upcase
            _, matching_header_value = headers.find { |h,| h.upcase == uppercased_header }
            matching_header_value
          end
        end
      end

      def self.tag_whitelisted_headers(request_span, whitelist, tagger, source)
        return if whitelist.nil?

        whitelist.each do |header|
          tag_name = tagger.name(header)
          next unless request_span.get_tag(tag_name).nil?

          tag_value = tagger.value(header, source)
          request_span.set_tag(tag_name, tag_value) if tag_value
        end
      end
    end
  end
end
