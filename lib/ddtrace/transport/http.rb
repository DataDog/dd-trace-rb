require 'ddtrace/version'
require 'ddtrace/ext/runtime'

require 'ddtrace/transport/http/builder'
require 'ddtrace/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'

module Datadog
  module Transport
    # Namespace for HTTP transport components
    module HTTP
      DEFAULT_AGENT_HOST = '127.0.0.1'.freeze
      DEFAULT_TRACE_AGENT_PORT = 8126
      DEFAULT_HEADERS = {
        'Datadog-Meta-Lang'.freeze => Datadog::Ext::Runtime::LANG,
        'Datadog-Meta-Lang-Version'.freeze => Datadog::Ext::Runtime::LANG_VERSION,
        'Datadog-Meta-Lang-Interpreter'.freeze => Datadog::Ext::Runtime::LANG_INTERPRETER,
        'Datadog-Meta-Tracer-Version'.freeze => Datadog::Ext::Runtime::TRACER_VERSION
      }.freeze

      module_function

      # Builds a new Transport::HTTP::Client
      def new(&block)
        Builder.new(&block).to_client
      end

      # Builds a new Transport::HTTP::Client with default settings
      # Pass a block to override any settings.
      def default(options = {})
        new do |transport|
          transport.adapter :net_http,
                            ENV.fetch('DD_AGENT_HOST', DEFAULT_AGENT_HOST),
                            ENV.fetch('DD_TRACE_AGENT_PORT', DEFAULT_TRACE_AGENT_PORT)

          transport.headers DEFAULT_HEADERS

          apis = API.defaults

          transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
          transport.api API::V3, apis[API::V3], fallback: API::V2
          transport.api API::V2, apis[API::V2]

          # Apply any settings given by options
          unless options.empty?
            # Change hostname/port
            if options.key?(:hostname) || options.key?(:port)
              hostname = options.fetch(:hostname, default_hostname)
              port = options.fetch(:port, default_port)
              transport.adapter :net_http, hostname, port
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

      def default_hostname
        ENV.fetch('DD_AGENT_HOST', DEFAULT_AGENT_HOST)
      end

      def default_port
        ENV.fetch('DD_TRACE_AGENT_PORT', DEFAULT_TRACE_AGENT_PORT)
      end

      # Add adapters to registry
      Builder::REGISTRY.set(Adapters::Net, :net_http)
      Builder::REGISTRY.set(Adapters::Test, :test)
      Builder::REGISTRY.set(Adapters::UnixSocket, :unix)
    end
  end
end
