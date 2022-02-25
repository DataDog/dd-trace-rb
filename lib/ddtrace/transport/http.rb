# typed: true

require 'uri'

require 'datadog/core/environment/container'
require 'datadog/core/environment/ext'
require 'ddtrace/transport/ext'
require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'
require 'ddtrace/transport/http/api'
require 'ddtrace/transport/http/builder'
require 'ddtrace/version'

module Datadog
  module Transport
    # Namespace for HTTP transport components
    module HTTP
      include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)

      module_function

      # Builds a new Transport::HTTP::Client
      def new(&block)
        Builder.new(&block).to_transport
      end

      # Builds a new Transport::HTTP::Client with default settings
      # Pass a block to override any settings.
      def default(
        agent_settings: Datadog::Core::Configuration::AgentSettingsResolver::ENVIRONMENT_AGENT_SETTINGS,
        **options
      )
        new do |transport|
          transport.adapter(agent_settings)
          transport.headers default_headers

          apis = API.defaults

          transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
          transport.api API::V3, apis[API::V3]

          # Apply any settings given by options
          unless options.empty?
            transport.default_api = options[:api_version] if options.key?(:api_version)
            transport.headers options[:headers] if options.key?(:headers)
          end

          if agent_settings.deprecated_for_removal_transport_configuration_proc
            agent_settings.deprecated_for_removal_transport_configuration_proc.call(transport)
          end

          # Call block to apply any customization, if provided
          yield(transport) if block_given?
        end
      end

      def default_headers
        {
          Datadog::Transport::Ext::HTTP::HEADER_META_LANG => Datadog::Core::Environment::Ext::LANG,
          Datadog::Transport::Ext::HTTP::HEADER_META_LANG_VERSION => Datadog::Core::Environment::Ext::LANG_VERSION,
          Datadog::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER => Datadog::Core::Environment::Ext::LANG_INTERPRETER,
          Datadog::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION => Datadog::Core::Environment::Ext::TRACER_VERSION
        }.tap do |headers|
          # Add container ID, if present.
          container_id = Datadog::Core::Environment::Container.container_id
          headers[Datadog::Transport::Ext::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
        end
      end

      def default_adapter
        Transport::Ext::HTTP::ADAPTER
      end

      def default_hostname(logger: Datadog.logger)
        logger.warn(
          'Deprecated for removal: Using #default_hostname for configuration is deprecated and will ' \
          'be removed on a future ddtrace release.'
        )

        Datadog::Core::Configuration::AgentSettingsResolver::ENVIRONMENT_AGENT_SETTINGS.hostname
      end

      def default_port(logger: Datadog.logger)
        logger.warn(
          'Deprecated for removal: Using #default_hostname for configuration is deprecated and will ' \
          'be removed on a future ddtrace release.'
        )

        Datadog::Core::Configuration::AgentSettingsResolver::ENVIRONMENT_AGENT_SETTINGS.port
      end

      def default_url(logger: Datadog.logger)
        logger.warn(
          'Deprecated for removal: Using #default_url for configuration is deprecated and will ' \
          'be removed on a future ddtrace release.'
        )

        nil
      end

      # Add adapters to registry
      Builder::REGISTRY.set(Adapters::Net, Transport::Ext::HTTP::ADAPTER)
      Builder::REGISTRY.set(Adapters::Test, Transport::Ext::Test::ADAPTER)
      Builder::REGISTRY.set(Adapters::UnixSocket, Transport::Ext::UnixSocket::ADAPTER)
    end
  end
end
