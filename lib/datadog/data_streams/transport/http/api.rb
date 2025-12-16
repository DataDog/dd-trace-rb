# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/api/map'
require_relative 'stats'

module Datadog
  module DataStreams
    module Transport
      module HTTP
        # Namespace for API components
        module API
          # API version
          V01 = 'v0.1'

          module_function

          def defaults
            Core::Transport::HTTP::API::Map[
              V01 => Stats::API::Endpoint.new(
                '/v0.1/pipeline_stats'
              ),
            ]
          end
        end
      end
    end
  end
end
