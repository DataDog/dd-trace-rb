require 'ddtrace/ext/http'

module Datadog
  module Contrib
    module Sinatra
      # Gets and sets trace information from a Rack headers Hash
      # TODO: Extract me?
      module Headers
        def response_header_tags(headers)
          headers ||= []

          {}.tap do |result|
            headers.each do |header|
              if key?(header)
                result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = self[header]
              else
                # Try a case-insensitive lookup
                uppercased_header = header.to_s.upcase
                matching_header = keys.find { |h| h.upcase == uppercased_header }
                if matching_header
                  result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = self[matching_header]
                end
              end
            end
          end
        end
      end
    end
  end
end
