# frozen_string_literal: true

require_relative '../../core/transport/http'
require_relative 'http/endpoint'
require_relative '../transport'

module Datadog
  module SymbolDatabase
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        # Symbol database upload endpoint
        # Uses multipart form-data for uploading compressed symbol data
        SYMDB_ENDPOINT = API::Endpoint.new(
          '/symdb/v1/input',
          Datadog::Core::Encoding::JSONEncoder
        )

        # Builds a new Transport::HTTP::Client for symbol database uploads
        # @param agent_settings [Core::Configuration::AgentSettingsResolver::AgentSettings]
        #   Agent connection settings (host, port, timeout, etc.)
        # @param logger [Logger] Logger instance
        # @param headers [Hash, nil] Optional additional headers
        # @return [Transport::Client] Transport client configured for symbol database
        def self.build(
          agent_settings:,
          logger: Datadog.logger,
          headers: nil
        )
          Core::Transport::HTTP.build(
            logger: logger,
            agent_settings: agent_settings,
            headers: headers
          ) do |transport|
            transport.api 'symdb', SYMDB_ENDPOINT, default: true

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end.to_transport(SymbolDatabase::Transport::Client)
        end
      end
    end
  end
end
