# frozen_string_literal: true

require_relative '../../core/transport/http'
require_relative 'http/api'
require_relative 'http/stats'
require_relative 'stats'

module Datadog
  module DataStreams
    module Transport
      # HTTP transport for Data Streams Monitoring
      module HTTP
        module_function

        # Builds a new Transport::HTTP::Client with default settings
        def default(
          agent_settings:,
          logger:
        )
          Core::Transport::HTTP.build(
            agent_settings: agent_settings,
            logger: logger,
            headers: {
              'Content-Type' => 'application/msgpack',
              'Content-Encoding' => 'gzip'
            }
          ) do |transport|
            apis = API.defaults

            transport.api API::V01, apis[API::V01], default: true

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end.to_transport(Transport::Stats::Transport)
        end
      end
    end
  end
end
