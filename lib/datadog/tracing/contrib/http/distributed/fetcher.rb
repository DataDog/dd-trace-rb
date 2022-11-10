# frozen_string_literal: true
# typed: false

require_relative '../../../distributed/fetcher'
require_relative '../../../../core/utils/refinement'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # Retrieves Rack formatted headers from HTTP headers.
          class Fetcher < Tracing::Distributed::Fetcher
            using Core::Utils::Refinement::String unless ::String.method_defined?(:+@)

            # TODO: Don't assume Rack format.
            #       Make distributed tracing headers apathetic.
            # DEV: Should we try to parse both verbatim an Rack-formatted headers,
            # DEV: given Rack-formatted is the most common format in Ruby?
            def [](name)
              # DEV: `String#+@` is not needed in Ruby >= 3.0, as interpolated strings are not frozen.
              rack_header = (+"http-#{name}").upcase!.tr('-', '_')

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
