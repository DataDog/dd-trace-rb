# frozen_string_literal: false
# typed: false

require_relative '../../../distributed/fetcher'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # Retrieves Rack formatted headers from HTTP headers.
          class Fetcher < Tracing::Distributed::Fetcher
            # TODO: Don't assume Rack format.
            #       Make distributed tracing headers apathetic.
            # DEV: Should we try to parse both verbatim an Rack-formatted headers,
            # DEV: given Rack-formatted is the most common format in Ruby?
            def [](name)
              rack_header = "HTTP-#{name}"
              rack_header.upcase!
              rack_header.tr!('-'.freeze, '_'.freeze)

              hdr = super(rack_header)

              # Only return the value if it is not an empty string
              hdr if hdr != ''
            end
          end
        end
      end
    end
  end
end
