# frozen_string_literal: true

require_relative '../../environment/container'
require_relative '../../environment/ext'
require_relative '../../transport/ext'
require_relative '../../transport/http'
require_relative 'config'
require_relative 'negotiation'

# TODO: Decouple transport/http
#
# Because a new transport is required for every (API, Client, Transport)
# triplet and endpoints cannot be negotiated independently, there can not be a
# single `default` transport, but only endpoint-specific ones.

module Datadog
  module Core
    module Remote
      module Transport
        # Namespace for HTTP transport components
        module HTTP
          ROOT = Negotiation::API::Endpoint.new(
            '/info',
          )

          V7 = Config::API::Endpoint.new(
            '/v0.7/config',
            Core::Encoding::JSONEncoder,
          )

          module_function

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def root(
            agent_settings:,
            logger:,
            headers: nil
          )
            Core::Transport::HTTP.build(
              agent_settings: agent_settings,
              logger: logger,
              headers: headers
            ) do |transport|
              transport.api 'root', ROOT

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end.to_transport(Core::Remote::Transport::Negotiation::Transport)
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def v7(
            agent_settings:,
            logger:,
            headers: nil
          )
            Core::Transport::HTTP.build(
              agent_settings: agent_settings,
              logger: logger,
              headers: headers
            ) do |transport|
              transport.api 'v7', V7

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end.to_transport(Core::Remote::Transport::Config::Transport)
          end
        end
      end
    end
  end
end
