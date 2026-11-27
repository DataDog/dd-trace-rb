# frozen_string_literal: true

require_relative "http/builder"
require_relative "http/adapters/net"
require_relative "http/adapters/unix_socket"
require_relative "http/adapters/test"
require_relative "http/adapters/native"
require_relative "../utils/only_once"
require_relative "../environment/container"
require_relative "../environment/ext"

module Datadog
  module Core
    module Transport
      # HTTP transport
      module HTTP
        # Add adapters to registry
        Builder::REGISTRY.set(
          Core::Transport::HTTP::Adapters::Net,
          Core::Configuration::Ext::Agent::HTTP::ADAPTER,
        )
        Builder::REGISTRY.set(
          Core::Transport::HTTP::Adapters::Test,
          Core::Transport::Ext::Test::ADAPTER,
        )
        Builder::REGISTRY.set(
          Core::Transport::HTTP::Adapters::UnixSocket,
          Core::Transport::Ext::UnixSocket::ADAPTER,
        )

        NATIVE_UNSUPPORTED_WARNING = Core::Utils::OnlyOnce.new
        private_constant :NATIVE_UNSUPPORTED_WARNING

        # Helper function that delegates to Builder.new
        # but is under HTTP namespace so that client code requires this file
        # to get the adapters configured, and not the builder directly.
        def self.build(
          agent_settings:,
          logger: Datadog.logger,
          headers: nil,
          native: true,
          &block
        )
          Builder.new(logger: logger) do |transport|
            transport.adapter((native && native_adapter(agent_settings, logger)) || agent_settings)
            transport.headers(default_headers)

            # The caller must define APIs before we set the default API.
            yield transport

            # Apply any settings given by options
            transport.headers(headers) if headers
          end
        end

        # The native HTTP adapter for the agent connection, if `agent.native_http` is enabled; `nil`, to use the
        # adapter of the agent settings (`Net::HTTP`), otherwise. Like for the native trace exporter, the native
        # adapter is only used if it is available: if not, a warning is logged once and the default is used.
        def self.native_adapter(agent_settings, logger)
          return unless Datadog.configuration.agent.native_http

          # The native adapter replaces the TCP and Unix socket ones: not, for example, the test adapter.
          return unless [
            Core::Configuration::Ext::Agent::HTTP::ADAPTER,
            Core::Configuration::Ext::Agent::UnixSocket::ADAPTER,
          ].include?(agent_settings.adapter)

          if (reason = Adapters::Native.unsupported_reason)
            NATIVE_UNSUPPORTED_WARNING.run do
              logger.warn(
                "Native HTTP client requested but not available: #{reason}. Falling back to the default HTTP client.",
              )
            end
            return
          end

          Adapters::Native.build(agent_settings)
        rescue => e
          logger.warn("Native HTTP client could not be created, falling back to the default HTTP client: #{e.class}: #{e.message}")
          nil
        end
        private_class_method :native_adapter

        def self.default_headers
          {
            Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => "1",
            Core::Transport::Ext::HTTP::HEADER_META_LANG =>
              Datadog::Core::Environment::Ext::LANG,
            Core::Transport::Ext::HTTP::HEADER_META_LANG_VERSION =>
              Datadog::Core::Environment::Ext::LANG_VERSION,
            Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER =>
              Datadog::Core::Environment::Ext::LANG_INTERPRETER,
            Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER_VENDOR =>
              Core::Environment::Ext::LANG_ENGINE,
            Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION =>
              Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION,
          }.tap do |headers|
            # Add application container info
            headers.merge!(Core::Environment::Container.to_headers)

            # TODO: inject configuration rather than reading from global here
            unless Datadog.configuration.apm.tracing.enabled
              # Sending this header to the agent will disable metrics computation (and billing) on the agent side
              # by pretending it has already been done on the library side.
              headers[Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS] = "yes"
            end
          end
        end
      end
    end
  end
end
