require 'ddtrace/transport/http/adapters/registry'
require 'ddtrace/transport/http/api/map'
require 'ddtrace/transport/http/api/instance'
require 'ddtrace/transport/http/client'

module Datadog
  module Transport
    module HTTP
      # Builds new instances of Transport::HTTP::Client
      class Builder
        REGISTRY = Adapters::Registry.new

        def initialize
          # Global settings
          @adapter = nil
          @headers = {}

          # Client settings
          @apis = API::Map.new
          @default_api = nil

          # API settings
          @api_options = {}

          yield(self)
        end

        def adapter(type, *args)
          @adapter = if type.is_a?(Symbol)
                       registry_klass = REGISTRY.get(type)
                       raise UnknownAdapterError, type if registry_klass.nil?
                       registry_klass.new(*args)
                     else
                       type
                     end
        end

        def headers(values = {})
          @headers.merge!(values)
        end

        # Adds a new API to the client
        # Valid options:
        #  - :adapter
        #  - :default
        #  - :fallback
        #  - :headers
        def api(key, routes, options = {})
          options = options.dup

          # Copy routes into API map
          @apis[key] = routes

          # Apply as default API, if specified to do so.
          @default_api = key if options.delete(:default) || @default_api.nil?

          # Save all other settings for initialization
          (@api_options[key] ||= {}).merge!(options)
        end

        def to_client
          @client ||= Client.new(
            build_api_instances,
            @default_api
          )
        end

        # Raised when the API cannot map the request to an endpoint.
        class UnknownAdapterError < StandardError
          attr_reader :type

          def initialize(type)
            @type = type
          end

          def message
            "Unknown transport adapter '#{type}'!"
          end
        end

        # Raised when the API cannot map the request to an endpoint.
        class NoAdapterError < StandardError
          attr_reader :key

          def initialize(key)
            @key = key
          end

          def message
            "No adapter configured for transport API '#{key}'!"
          end
        end

        private

        def build_api_instances
          @apis.inject(API::Map.new) do |instances, (key, routes)|
            instances.tap do
              api_options = @api_options[key].dup

              # Resolve the adapter to use for this API
              adapter = api_options.delete(:adapter) || @adapter
              raise NoAdapterError, key if adapter.nil?

              # Resolve fallback and merge headers
              fallback = api_options.delete(:fallback)
              (api_options[:headers] ||= {}).merge!(@headers)

              # Add API::Instance with all settings
              instances[key] = API::Instance.new(
                adapter,
                routes,
                api_options
              )

              # Configure fallback, if provided.
              instances.with_fallbacks(key => fallback) unless fallback.nil?
            end
          end
        end
      end
    end
  end
end
