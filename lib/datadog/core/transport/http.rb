# typed: true
require 'uri'

require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/environment/ext'
require 'datadog/core/transport/ext'
require 'datadog/core/environment/container'
require 'datadog/core/transport/http/builder'
require 'datadog/core/transport/http/adapters/net'
require 'datadog/core/transport/http/adapters/test'
require 'datadog/core/transport/http/adapters/unix_socket'

module Datadog
  module Core
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

            if agent_settings.deprecated_for_removal_transport_configuration_options
              # The deprecated_for_removal_transport_configuration_options take precedence over any options the caller
              # specifies
              options = options.merge(**agent_settings.deprecated_for_removal_transport_configuration_options)
            end

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
            Ext::HTTP::HEADER_META_LANG => Core::Environment::Ext::LANG,
            Ext::HTTP::HEADER_META_LANG_VERSION => Core::Environment::Ext::LANG_VERSION,
            Ext::HTTP::HEADER_META_LANG_INTERPRETER => Core::Environment::Ext::LANG_INTERPRETER
          }.tap do |headers|
            # Add container ID, if present.
            container_id = Core::Environment::Container.container_id
            headers[Ext::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
          end
        end

        def default_adapter
          Ext::HTTP::ADAPTER
        end

        def default_hostname(logger: Datadog.logger)
          logger.warn(
            'Deprecated for removal: Using #default_hostname for configuration is deprecated and will ' \
            'be removed on a future ddtrace release.'
          )

          Core::Configuration::AgentSettingsResolver::ENVIRONMENT_AGENT_SETTINGS.hostname
        end

        def default_port(logger: Datadog.logger)
          logger.warn(
            'Deprecated for removal: Using #default_hostname for configuration is deprecated and will ' \
            'be removed on a future ddtrace release.'
          )

          Core::Configuration::AgentSettingsResolver::ENVIRONMENT_AGENT_SETTINGS.port
        end

        def default_url(logger: Datadog.logger)
          logger.warn(
            'Deprecated for removal: Using #default_url for configuration is deprecated and will ' \
            'be removed on a future ddtrace release.'
          )

          nil
        end

        # Add adapters to registry
        Builder::REGISTRY.set(Adapters::Net, Ext::HTTP::ADAPTER)
        Builder::REGISTRY.set(Adapters::Test, Ext::Test::ADAPTER)
        Builder::REGISTRY.set(Adapters::UnixSocket, Ext::UnixSocket::ADAPTER)
      end
    end
  end
end
