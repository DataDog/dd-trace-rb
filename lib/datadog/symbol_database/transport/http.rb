# frozen_string_literal: true

require_relative '../../core/encoding'
require_relative '../../core/transport/http'
require_relative 'http/endpoint'
require_relative '../transport'

module Datadog
  module SymbolDatabase
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        # POST endpoint for the agent's symbol database intake.
        # Multipart form-data is dispatched via `env.form` from the
        # `Symbols::Client` subclass.
        SYMBOLS_ENDPOINT = API::Endpoint.new(
          '/symdb/v1/input',
          Datadog::Core::Encoding::JSONEncoder,
        )

        # Builds a transport for the symbols upload endpoint.
        # @param agent_settings [Core::Configuration::AgentSettingsResolver::AgentSettings]
        #   Agent connection settings (host, port, timeout, etc.)
        # @param logger [Logger] Logger instance
        # @param headers [Hash, nil] Optional additional headers
        # @return [Symbols::Transport] Transport for the symbols endpoint
        def self.symbols(
          agent_settings:,
          logger:,
          headers: nil
        )
          Core::Transport::HTTP.build(
            logger: logger,
            agent_settings: agent_settings,
            headers: headers,
          ) do |transport|
            transport.api 'symbols', SYMBOLS_ENDPOINT, default: true

            yield(transport) if block_given?
          end.to_transport(SymbolDatabase::Transport::Symbols::Transport)
        end
      end
    end
  end
end
