# frozen_string_literal: true

require_relative 'http/builder'
require_relative 'http/adapters/net'
require_relative 'http/adapters/unix_socket'
require_relative 'http/adapters/test'

module Datadog
  module Core
    module Transport
      # HTTP transport
      module HTTP
        # Add adapters to registry
        Builder::REGISTRY.set(
          Core::Transport::HTTP::Adapters::Net,
          Core::Configuration::Ext::Agent::HTTP::ADAPTER
        )
        Builder::REGISTRY.set(
          Core::Transport::HTTP::Adapters::Test,
          Core::Transport::Ext::Test::ADAPTER
        )
        Builder::REGISTRY.set(
          Core::Transport::HTTP::Adapters::UnixSocket,
          Core::Transport::Ext::UnixSocket::ADAPTER
        )

        module_function

        # Helper function that delegates to Builder.new
        # but is under HTTP namespace so that client code requires this file
        # to get the adapters configured, and not the builder directly.
        def build(
          agent_settings:,
          logger: Datadog.logger,
          headers: nil,
          &block
        )
          Builder.new(logger: logger) do |transport|
            transport.adapter(agent_settings)
            transport.headers(default_headers)

            # The caller must define APIs before we set the default API.
            yield transport

            # Apply any settings given by options
            transport.headers(headers) if headers
          end
        end

        def default_headers
          {
            Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => '1',
            Core::Transport::Ext::HTTP::HEADER_META_LANG =>
              Datadog::Core::Environment::Ext::LANG,
            Core::Transport::Ext::HTTP::HEADER_META_LANG_VERSION =>
              Datadog::Core::Environment::Ext::LANG_VERSION,
            Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER =>
              Datadog::Core::Environment::Ext::LANG_INTERPRETER,
            Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER_VENDOR =>
              Core::Environment::Ext::LANG_ENGINE,
            Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION =>
              Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION
          }.tap do |headers|
            # Add application container info
            headers.merge!(Core::Environment::Container.to_headers)

            # TODO: inject configuration rather than reading from global here
            unless Datadog.configuration.apm.tracing.enabled
              # Sending this header to the agent will disable metrics computation (and billing) on the agent side
              # by pretending it has already been done on the library side.
              headers[Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS] = 'yes'
            end
          end
        end
      end
    end
  end
end
