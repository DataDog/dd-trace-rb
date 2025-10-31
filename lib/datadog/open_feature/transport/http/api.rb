# frozen_string_literal: true

require_relative '../../../core/encoding'
require_relative '../../../core/transport/http/api/map'

require_relative 'exposures'

module Datadog
  module OpenFeature
    module Transport
      module HTTP
        # Namespace for API components
        module API
          EXPOSURES = 'exposures'

          module_function

          def defaults
            Datadog::Core::Transport::HTTP::API::Map[
              EXPOSURES => Exposures::API::Spec.new do |spec|
                spec.exposures = Exposures::API::Endpoint.new(
                  '/evp_proxy/v2/api/v2/exposures',
                  Datadog::Core::Encoding::JSONEncoder
                )
              end
            ]
          end
        end
      end
    end
  end
end
