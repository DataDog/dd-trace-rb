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

        attr_reader \
          :apis,
          :api_options,
          :default_adapter,
          :default_api,
          :default_headers

        def initialize
          # Global settings
          @default_adapter = nil
          @default_headers = {}

          # Client settings
          @apis = API::Map.new
          @default_api = nil

          # API settings
          @api_options = {}

          yield(self) if block_given?
        end

        def adapter(type, *args)
          @default_adapter = if type.is_a?(Symbol)
                               registry_klass = REGISTRY.get(type)
                               raise UnknownAdapterError, type if registry_klass.nil?
                               registry_klass.new(*args)
                             else
                               type
                             end
        end

        def headers(values = {})
          @default_headers.merge!(values)
        end

        # Adds a new API to the client
        # Valid options:
        #  - :adapter
        #  - :default
        #  - :fallback
        #  - :headers
        def api(key, spec, options = {})
          options = options.dup

          # Copy spec into API map
          @apis[key] = spec

          # Apply as default API, if specified to do so.
          @default_api = key if options.delete(:default) || @default_api.nil?

          # Save all other settings for initialization
          (@api_options[key] ||= {}).merge!(options)
        end

        def default_api=(key)
          raise UnknownApiError, key unless @apis.key?(key)
          @default_api = key
        end

        def to_transport
          raise NoDefaultApiError if @default_api.nil?

          # DEV: Should not be specific to traces
          Transport::Traces::Transport.new(to_api_instances, @default_api)
        end

        def to_api_instances
          raise NoApisError if @apis.empty?

          @apis.inject(API::Map.new) do |instances, (key, spec)|
            instances.tap do
              api_options = @api_options[key].dup

              # Resolve the adapter to use for this API
              adapter = api_options.delete(:adapter) || @default_adapter
              raise NoAdapterForApiError, key if adapter.nil?

              # Resolve fallback and merge headers
              fallback = api_options.delete(:fallback)
              api_options[:headers] = @default_headers.merge((api_options[:headers] || {}))

              # Add API::Instance with all settings
              instances[key] = api_instance_class.new(
                spec,
                adapter,
                api_options
              )

              # Configure fallback, if provided.
              instances.with_fallbacks(key => fallback) unless fallback.nil?
            end
          end
        end

        def api_instance_class
          API::Instance
        end

        # Raised when the API key does not match known APIs.
        class UnknownApiError < StandardError
          attr_reader :key

          def initialize(key)
            @key = key
          end

          def message
            "Unknown transport API '#{key}'!"
          end
        end

        # Raised when the identifier cannot be matched to an adapter.
        class UnknownAdapterError < StandardError
          attr_reader :type

          def initialize(type)
            @type = type
          end

          def message
            "Unknown transport adapter '#{type}'!"
          end
        end

        # Raised when an adapter cannot be resolved for an API instance.
        class NoAdapterForApiError < StandardError
          attr_reader :key

          def initialize(key)
            @key = key
          end

          def message
            "No adapter resolved for transport API '#{key}'!"
          end
        end

        # Raised when built without defining APIs.
        class NoApisError < StandardError
          def message
            'No APIs configured for transport!'
          end
        end

        # Raised when client built without defining a default API.
        class NoDefaultApiError < StandardError
          def message
            'No default API configured for transport!'
          end
        end
      end
    end
  end
end
