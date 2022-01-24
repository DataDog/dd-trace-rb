# typed: true

require 'forwardable'

require 'datadog/core/transport/http'
require 'datadog/core/environment/ext'

require 'ddtrace/transport/http/api'
require 'ddtrace/ext/transport'

module Datadog
  module Transport
    # Namespace for HTTP transport components
    module HTTP
      module_function

      # Builds a new Transport::HTTP::Client with default settings
      # Pass a block to override any settings.
      def default(**options)
        Datadog::Core::Transport::HTTP.default(**options) do
          apis = API.defaults

          transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
          transport.api API::V3, apis[API::V3]

          transport.default_api = options[:api_version] if options.key?(:api_version)

          # Call block to apply any customization, if provided
          yield(transport) if block_given?
        end
      end

      def default_headers
        Datadog::Core::Transport::HTTP.merge(
          Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Datadog::Core::Environment::Ext::TRACER_VERSION
        )
      end

      # Forward other methods to core module
      singleton_class.instance_eval do
        extend Forwardable
    
        def_delegators \
          Datadog::Core::Transport::HTTP,
          :new,
          :default_adapter,
          :default_hostname,
          :default_port,
          :default_url
      end
    end
  end
end
