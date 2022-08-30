require_relative '../../client_ip'

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Classes and utilities for handling headers in Rack.
        module Header
          # An implementation of a header collection that looks up headers from a Rack environment.
          class RequestHeaderCollection < Datadog::Tracing::ClientIp::HeaderCollection
            # Creates a header collection from a rack environment.
            def initialize(env)
              super()
              @env = env
            end

            # Gets the value of the header with the given name.
            def get(header_name)
              @env[Header.header_to_rack_header(header_name)]
            end

            # Tests whether a header with the given name exists in the environment.
            def key?(header_name)
              @env.key?(Header.header_to_rack_header(header_name))
            end
          end

          def self.header_to_rack_header(name)
            "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
          end
        end
      end
    end
  end
end
