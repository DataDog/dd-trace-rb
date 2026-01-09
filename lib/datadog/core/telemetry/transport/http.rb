# frozen_string_literal: true

require_relative '../../encoding'
require_relative '../../transport/http'
require_relative 'telemetry'

module Datadog
  module Core
    module Telemetry
      module Transport
        # Namespace for HTTP transport components
        module HTTP
          AGENT_TELEMETRY = Telemetry::API::Endpoint.new(
            '/telemetry/proxy/api/v2/apmtelemetry',
            Core::Encoding::JSONEncoder,
          )

          AGENTLESS_TELEMETRY = Telemetry::API::Endpoint.new(
            '/api/v2/apmtelemetry',
            Core::Encoding::JSONEncoder,
          )

          module_function

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def agentless_telemetry(
            agent_settings:,
            logger:,
            api_key: nil,
            headers: nil
          )
            Core::Transport::HTTP.build(
              logger: logger,
              agent_settings: agent_settings,
              headers: headers
            ) do |transport|
              transport.api 'agentless_telemetry', AGENTLESS_TELEMETRY
              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end.to_transport(Core::Telemetry::Transport::Telemetry::Transport).tap do |transport|
              transport.api_key = api_key
            end
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def agent_telemetry(
            agent_settings:,
            logger:,
            headers: nil
          )
            Core::Transport::HTTP.build(
              logger: logger,
              agent_settings: agent_settings,
              headers: headers
            ) do |transport|
              transport.api 'agent_telemetry', AGENT_TELEMETRY

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end.to_transport(Core::Telemetry::Transport::Telemetry::Transport)
          end
        end
      end
    end
  end
end
