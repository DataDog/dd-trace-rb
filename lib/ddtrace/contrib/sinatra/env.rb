require 'ddtrace/ext/http'

module Datadog
  module Contrib
    module Sinatra
      # Gets and sets trace information from a Rack Env
      # TODO: Extract me?
      module Env
        ENV_SPAN = 'datadog.sinatra_request_span'.freeze

        def datadog_span
          self[ENV_SPAN]
        end

        def datadog_span=(span)
          self[ENV_SPAN] = span
        end

        def request_header_tags(headers)
          headers ||= []

          {}.tap do |result|
            headers.each do |header|
              rack_header = header_to_rack_header(header)
              if key?(rack_header)
                result[Datadog::Ext::HTTP::RequestHeaders.to_tag(header)] = self[rack_header]
              end
            end
          end
        end

        private

        def header_to_rack_header(name)
          "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
        end
      end
    end
  end
end
