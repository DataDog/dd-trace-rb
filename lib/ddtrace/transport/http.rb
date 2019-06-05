require 'ddtrace/version'

require 'ddtrace/transport/http/builder'
require 'ddtrace/transport/http/api'

require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/net'

module Datadog
  module Transport
    # Namespace for HTTP transport components
    module HTTP
      DEFAULT_AGENT_HOST = '127.0.0.1'.freeze
      DEFAULT_TRACE_AGENT_PORT = 8126

      module_function

      # Builds a new Transport::HTTP::Client
      def new(&block)
        Builder.new(&block).to_client
      end

      # Builds a new Transport::HTTP::Client with default settings
      # Pass a block to override any settings.
      def default
        new do |transport|
          transport.adapter :net_http,
                            ENV.fetch('DD_AGENT_HOST', DEFAULT_AGENT_HOST),
                            ENV.fetch('DD_TRACE_AGENT_PORT', DEFAULT_TRACE_AGENT_PORT)

          transport.headers 'Datadog-Meta-Lang' => 'ruby',
                            'Datadog-Meta-Lang-Version' => RUBY_VERSION,
                            'Datadog-Meta-Lang-Interpreter' => RUBY_ENGINE,
                            'Datadog-Meta-Tracer-Version' => Datadog::VERSION::STRING

          apis = API.defaults

          transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
          transport.api API::V3, apis[API::V3], fallback: API::V2
          transport.api API::V2, apis[API::V2]

          # Call block to apply any customization, if provided.
          yield(transport) if block_given?
        end
      end

      # Add adapters to registry
      Builder::REGISTRY.set(Adapters::Test, :test)
      Builder::REGISTRY.set(Adapters::Net, :net_http)
    end
  end
end
