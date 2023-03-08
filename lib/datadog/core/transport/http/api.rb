# frozen_string_literal: true

require_relative '../../encoding'

require_relative '../../../../ddtrace/transport/http/api/map'

# TODO: Decouple standard transport/http/api/instance
#
# Separate classes are needed because transport/http/trace includes
# Trace::API::Instance which closes over and uses a single spec, which is
# negotiated as either /v3 or /v4 for the whole API at the spec level, but we
# need an independent toplevel path at the endpoint level.
#
# Separate classes are needed because of `include Trace::API::Instance`.
#
# Below should be:
# require_relative '../../../../ddtrace/transport/http/api/spec'
require_relative 'api/spec'

# TODO: only needed for Negotiation::API::Endpoint
require_relative 'negotiation'

module Datadog
  module Core
    module Transport
      module HTTP
        # Namespace for API components
        module API
          # Default API versions
          ROOT = 'root'

          module_function

          def defaults
            Datadog::Transport::HTTP::API::Map[
              ROOT => Spec.new do |s|
                s.info = Negotiation::API::Endpoint.new(
                  '/info',
                )
              end,
            ]
          end
        end
      end
    end
  end
end
