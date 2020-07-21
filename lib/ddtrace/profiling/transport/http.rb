require 'ddtrace/ext/runtime'
require 'ddtrace/ext/transport'

require 'ddtrace/runtime/container'

require 'ddtrace/profiling/transport/http/builder'
require 'ddtrace/profiling/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'

module Datadog
  module Profiling
    module Transport
      # TODO: Consolidate with Dataog::Transport::HTTP
      # Namespace for HTTP transport components
      module HTTP
        module_function

        # Builds a new Transport::HTTP::Client
        def new(&block)
          Builder.new(&block).to_transport
        end

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def default(options = {})
          new do |transport|
            transport.headers default_headers

            # Configure adapter & API
            if options[:site] && options[:api_key]
              configure_for_agentless(transport, options)
            else
              configure_for_agent(transport, options)
            end

            # Additional options
            unless options.empty?
              # Change default API
              transport.default_api = options[:api_version] if options.key?(:api_version)

              # Add headers
              transport.headers options[:headers] if options.key?(:headers)

              # Execute on_build callback
              options[:on_build].call(transport) if options[:on_build].is_a?(Proc)
            end

            # Call block to apply any customization, if provided.
            yield(transport) if block_given?
          end
        end

        def default_headers
          {
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG => Datadog::Ext::Runtime::LANG,
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG_VERSION => Datadog::Ext::Runtime::LANG_VERSION,
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG_INTERPRETER => Datadog::Ext::Runtime::LANG_INTERPRETER,
            Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Datadog::Ext::Runtime::TRACER_VERSION
          }.tap do |headers|
            # Add container ID, if present.
            container_id = Datadog::Runtime::Container.container_id
            unless container_id.nil?
              headers[Datadog::Ext::Transport::HTTP::HEADER_CONTAINER_ID] = container_id
            end
          end
        end

        def default_adapter
          :net_http
        end

        def default_hostname
          ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST, Datadog::Ext::Transport::HTTP::DEFAULT_HOST)
        end

        def default_port
          ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT, Datadog::Ext::Transport::HTTP::DEFAULT_PORT).to_i
        end

        def configure_for_agent(transport, options = {})
          apis = API.agent_defaults

          hostname = options[:hostname] || default_hostname
          port = options[:port] || default_port

          adapter_options = {}
          adapter_options[:timeout] = options[:timeout] if options.key?(:timeout)
          adapter_options[:ssl] = options[:ssl] if options.key?(:ssl)

          transport.adapter default_adapter, hostname, port, adapter_options
          transport.api API::V1, apis[API::V1], default: true
        end

        def configure_for_agentless(transport, options = {})
          apis = API.api_defaults

          site_uri = URI(format(Datadog::Ext::Profiling::Transport::HTTP::URI_TEMPLATE_DD_API, options[:site]))
          hostname = options[:hostname] || site_uri.host
          port = options[:port] || site_uri.port

          adapter_options = {}
          adapter_options[:timeout] = options[:timeout] if options.key?(:timeout)
          adapter_options[:ssl] = options[:ssl] || (site_uri.scheme == 'https'.freeze)

          transport.adapter default_adapter, hostname, port, adapter_options
          transport.api API::V1, apis[API::V1], default: true
          transport.headers(Datadog::Ext::Transport::HTTP::HEADER_DD_API_KEY => options[:api_key])
        end

        # Add adapters to registry
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Net, :net_http)
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Test, :test)
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::UnixSocket, :unix)

        private \
          :configure_for_agent,
          :configure_for_agentless
      end
    end
  end
end
