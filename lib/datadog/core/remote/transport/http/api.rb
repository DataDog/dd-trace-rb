# frozen_string_literal: true

require_relative '../../../encoding'
require_relative '../../../transport/http/api/endpoint'
require_relative '../../../transport/http/api/map'
require_relative 'negotiation'
require_relative 'config'

module Datadog
  module Core
    module Remote
      module Transport
        module HTTP
          # Namespace for API components
          module API
            # Default API versions
            ROOT = 'root'
            V7 = 'v0.7'

            module_function

            def defaults
              Core::Transport::HTTP::API::Map[
                ROOT => Negotiation::API::Endpoint.new(
                  '/info',
                ),
                V7 => Config::API::Endpoint.new(
                  '/v0.7/config',
                  Core::Encoding::JSONEncoder,
                ),
              ]
            end
          end
        end
      end
    end
  end
end
