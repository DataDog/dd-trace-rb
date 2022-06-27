# typed: false
require 'datadog/tracing/distributed/helpers'

module Datadog
  module Tracing
    module Distributed
      module Headers
        # Parser provides easy access and validation methods for Rack headers
        class Parser
          def initialize(env)
            @env = env
          end

          # TODO: Don't assume Rack format.
          #       Make distributed tracing headers apathetic.
          def header(name)
            rack_header = "http-#{name}".upcase!.tr('-', '_')

            hdr = @env[rack_header]

            # Only return the value if it is not an empty string
            hdr if hdr != ''
          end

          def id(hdr, base = 10)
            Helpers.value_to_id(header(hdr), base)
          end

          def number(hdr, base = 10)
            Helpers.value_to_number(header(hdr), base)
          end
        end
      end
    end
  end
end
