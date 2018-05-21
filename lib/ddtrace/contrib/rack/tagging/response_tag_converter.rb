require 'ddtrace/utils/base_tag_converter'

module Datadog
  module Contrib
    module Rack
      module Tagging
        # Tag headers from Rack responses
        class ResponseTagConverter < Datadog::Utils::BaseTagConverter
          include Singleton

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
      end
    end
  end
end
