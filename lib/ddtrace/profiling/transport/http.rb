require 'datadog/core/environment/ext'
require 'ddtrace/ext/transport'

require 'datadog/core/environment/container'

require 'ddtrace/profiling/transport/http/builder'
require 'ddtrace/profiling/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'

module Datadog
  module Profiling
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        module_function

        # Builds a new Transport::HTTP::Client
        def new(&block)
          Builder.new(&block).to_transport
        end

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def default(profiling_upload_timeout_seconds:, agent_settings: nil, site: nil, api_key: nil)
          new do |transport|
            transport.headers default_headers

            # Configure adapter & API
            if site && api_key
              configure_for_agentless(
                transport,
                profiling_upload_timeout_seconds: profiling_upload_timeout_seconds,
                site: site,
                api_key: api_key
              )
            else
              unless agent_settings
                raise(
                  ArgumentError,
                  "Missing configuration for #{self}.default: All of `agent_settings`, `site` and `api_key` are nil"
                )
              end

              configure_for_agent(
                transport,
                profiling_upload_timeout_seconds: profiling_upload_timeout_seconds,
                agent_settings: agent_settings
              )
            end
          end
        end

        def default_headers
          {
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG => Core::Environment::Ext::LANG,
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG_VERSION => Core::Environment::Ext::LANG_VERSION,
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG_INTERPRETER => Core::Environment::Ext::LANG_INTERPRETER,
            Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Core::Environment::Ext::TRACER_VERSION
          }.tap do |headers|
            # Add container ID, if present.
            container_id = Datadog::Core::Environment::Container.container_id
            headers[Datadog::Ext::Transport::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
          end
        end

        private_class_method def default_adapter
          :net_http
        end

        private_class_method def configure_for_agent(transport, profiling_upload_timeout_seconds:, agent_settings:)
          apis = API.agent_defaults

          transport.adapter(
            default_adapter,
            agent_settings.hostname,
            agent_settings.port,
            # We explictly use profiling_upload_timeout_seconds instead of agent_settings.timeout because profile
            # uploads are bigger and thus we employ a separate configuration.
            timeout: profiling_upload_timeout_seconds,
            ssl: agent_settings.ssl
          )
          transport.api(API::V1, apis[API::V1], default: true)

          # NOTE: This proc, when it exists, usually overrides the transport specified above
          if agent_settings.deprecated_for_removal_transport_configuration_proc
            agent_settings.deprecated_for_removal_transport_configuration_proc.call(transport)
          end
        end

        private_class_method def configure_for_agentless(transport, profiling_upload_timeout_seconds:, site:, api_key:)
          apis = API.api_defaults

          site_uri = URI(format(Datadog::Ext::Profiling::Transport::HTTP::URI_TEMPLATE_DD_API, site))
          hostname = site_uri.host
          port = site_uri.port

          transport.adapter(
            default_adapter,
            hostname,
            port,
            timeout: profiling_upload_timeout_seconds,
            ssl: site_uri.scheme == 'https'
          )
          transport.api(API::V1, apis[API::V1], default: true)
          transport.headers(Datadog::Ext::Transport::HTTP::HEADER_DD_API_KEY => api_key)
        end

        # Add adapters to registry
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Net, :net_http)
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Test, :test)
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::UnixSocket, :unix)
      end
    end
  end
end
