require_relative '../../metadata/ext'

module Datadog
  module Tracing
    module Contrib
      module Sinatra
        # Gets and sets trace information from a Rack headers Hash
        module Headers
          module_function

          def response_header_tags(headers, target_headers)
            target_headers ||= []

            {}.tap do |result|
              target_headers.each do |header|
                if headers.key?(header)
                  result[Tracing::Metadata::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[header]
                else
                  # Try a case-insensitive lookup
                  uppercased_header = header.to_s.upcase
                  matching_header = headers.keys.find { |h| h.upcase == uppercased_header }
                  if matching_header
                    result[Tracing::Metadata::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[matching_header]
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
