require 'ddtrace/version'
require 'ddtrace/ext/runtime'
require 'ddtrace/ext/transport'

require 'ddtrace/runtime/container'

require 'ddtrace/transport/http/builder'
require 'ddtrace/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'
require 'uri'

module Datadog
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
      def default(options = {})
        new do |transport|
          transport.adapter default_adapter, default_hostname, default_port
          transport.headers default_headers

          apis = API.defaults

          transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
          transport.api API::V3, apis[API::V3], fallback: API::V2
          transport.api API::V2, apis[API::V2]

          # Apply any settings given by options
          unless options.empty?
            # Change hostname/port
            if [:hostname, :port, :timeout, :ssl].any? { |key| options.key?(key) }
              hostname = options[:hostname] || default_hostname
              port = options[:port] || default_port

              adapter_options = {}
              adapter_options[:timeout] = options[:timeout] if options.key?(:timeout)
              adapter_options[:ssl] = options[:ssl] if options.key?(:ssl)

              transport.adapter default_adapter, hostname, port, adapter_options
            end

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
        return default_url.hostname if default_url

        ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST, Datadog::Ext::Transport::HTTP::DEFAULT_HOST)
      end

      def default_port
        return default_url.port if default_url

        ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT, Datadog::Ext::Transport::HTTP::DEFAULT_PORT).to_i
      end

      def default_url
        url_env = ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL, nil)

        if url_env
          uri_parsed = URI.parse(url_env)

          uri_parsed if %w[http https].include?(uri_parsed.scheme)
        end
      end

      # Add adapters to registry
      Builder::REGISTRY.set(Adapters::Net, :net_http)
      Builder::REGISTRY.set(Adapters::Test, :test)
      Builder::REGISTRY.set(Adapters::UnixSocket, :unix)
    end
  end
end
