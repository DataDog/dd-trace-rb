# typed: true

require 'datadog/core/environment/ext'
require 'ddtrace/transport/ext'

require 'datadog/core/environment/container'
require 'datadog/core/environment/variable_helpers'

require 'datadog/profiling/transport/http/builder'
require 'datadog/profiling/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'

module Datadog
  module Profiling
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        # Builds a new Transport::HTTP::Client
        def self.new(&block)
          Builder.new(&block).to_transport
        end

        # Builds a new Transport::HTTP::Client with default settings
        def self.default(
          profiling_upload_timeout_seconds:,
          agent_settings:,
          site: nil,
          api_key: nil,
          agentless_allowed: agentless_allowed?
        )
          new do |transport|
            transport.headers default_headers

            # Configure adapter & API
            if site && api_key && agentless_allowed
              configure_for_agentless(
                transport,
                profiling_upload_timeout_seconds: profiling_upload_timeout_seconds,
                site: site,
                api_key: api_key
              )
            else
              configure_for_agent(
                transport,
                profiling_upload_timeout_seconds: profiling_upload_timeout_seconds,
                agent_settings: agent_settings
              )
            end
          end
        end

        def self.default_headers
          {
            Datadog::Transport::Ext::HTTP::HEADER_META_LANG => Core::Environment::Ext::LANG,
            Datadog::Transport::Ext::HTTP::HEADER_META_LANG_VERSION => Core::Environment::Ext::LANG_VERSION,
            Datadog::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER => Core::Environment::Ext::LANG_INTERPRETER,
            Datadog::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION => Core::Environment::Ext::TRACER_VERSION
          }.tap do |headers|
            # Add container ID, if present.
            container_id = Core::Environment::Container.container_id
            headers[Datadog::Transport::Ext::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
          end
        end

        private_class_method def self.configure_for_agent(transport, profiling_upload_timeout_seconds:, agent_settings:)
          apis = API.agent_defaults

          transport.adapter(agent_settings.merge(timeout_seconds: profiling_upload_timeout_seconds))
          transport.api(API::V1, apis[API::V1], default: true)

          # NOTE: This proc, when it exists, usually overrides the transport specified above
          if agent_settings.deprecated_for_removal_transport_configuration_proc
            agent_settings.deprecated_for_removal_transport_configuration_proc.call(transport)
          end
        end

        private_class_method def self.configure_for_agentless(transport, profiling_upload_timeout_seconds:, site:, api_key:)
          apis = API.api_defaults

          site_uri = URI(format(Profiling::OldExt::Transport::HTTP::URI_TEMPLATE_DD_API, site))
          hostname = site_uri.host
          port = site_uri.port

          transport.adapter(
            Datadog::Transport::Ext::HTTP::ADAPTER,
            hostname,
            port,
            timeout: profiling_upload_timeout_seconds,
            ssl: site_uri.scheme == 'https'
          )
          transport.api(API::V1, apis[API::V1], default: true)
          transport.headers(Datadog::Transport::Ext::HTTP::HEADER_DD_API_KEY => api_key)
        end

        private_class_method def self.agentless_allowed?
          Core::Environment::VariableHelpers.env_to_bool(Profiling::Ext::ENV_AGENTLESS, false)
        end

        # Add adapters to registry
        Datadog::Transport::HTTP::Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Net,
                                                        Datadog::Transport::Ext::HTTP::ADAPTER)
        Datadog::Transport::HTTP::Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Test,
                                                        Datadog::Transport::Ext::Test::ADAPTER)
        Datadog::Transport::HTTP::Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::UnixSocket,
                                                        Datadog::Transport::Ext::UnixSocket::ADAPTER)
      end
    end
  end
end
