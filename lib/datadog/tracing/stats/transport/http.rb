# frozen_string_literal: true

require_relative '../../../core/transport/http'
require_relative 'http/stats'
require_relative 'stats'

module Datadog
  module Tracing
    module Stats
      module Transport
        # HTTP transport for client-side trace stats
        module HTTP
          V06 = StatsEndpoint::API::Endpoint.new(
            '/v0.6/stats'
          )

          module_function

          # Builds a new Transport::HTTP::Client with default settings
          def default(
            agent_settings:,
            logger:
          )
            Core::Transport::HTTP.build(
              agent_settings: agent_settings,
              logger: logger,
            ) do |transport|
              transport.api 'v0.6', V06, default: true

              yield(transport) if block_given?
            end.to_transport(StatsTransport::Transport)
          end
        end
      end
    end
  end
end
