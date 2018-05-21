require 'ddtrace/utils/base_tag_converter'

module Datadog
  module Contrib
    module Rack
      module Tagging
        # Tag headers from Rack requests
        class RequestTagConverter < Datadog::Utils::BaseTagConverter
          include Singleton

          def name(header)
            Datadog::Ext::HTTP::RequestHeaders.to_tag(header)
          end

          def value(header, env)
            rack_header = "HTTP_#{header.to_s.upcase.gsub(/[-\s]/, '_')}"

            env[rack_header]
          end
        end
      end
    end
  end
end
