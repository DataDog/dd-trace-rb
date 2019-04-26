require 'ddtrace/encoding'
require 'ddtrace/version'

require 'ddtrace/transport/traces'
require 'ddtrace/transport/http/api'
require 'ddtrace/transport/http/api_map'
require 'ddtrace/transport/http/endpoint'

require 'ddtrace/transport/http/compatibility'

module Datadog
  module Transport
    module HTTP
      # Routes, encodes, and sends tracer data to the trace agent via HTTP.
      class Client
        include Compatibility

        attr_reader \
          :service,
          :apis,
          :active_api,
          :encoder,
          :headers

        DEFAULT_APIS = APIMap[
          V4 = 'v0.4'.freeze => API.new(
            Transport::Traces::Parcel => TracesEndpoint.new('/v0.4/traces'.freeze, Encoding::MsgpackEncoder)
          ),
          V3 = 'v0.3'.freeze => API.new(
            Transport::Traces::Parcel => TracesEndpoint.new('/v0.3/traces'.freeze, Encoding::MsgpackEncoder)
          ),
          V2 = 'v0.2'.freeze => API.new(
            Transport::Traces::Parcel => TracesEndpoint.new('/v0.2/traces'.freeze, Encoding::JSONEncoder)
          )
        ].with_fallbacks(V4 => V3, V3 => V2).freeze

        def initialize(service, options = {})
          @service = service
          @apis = options[:apis] || DEFAULT_APIS

          # Select active API
          @active_api = apis[options.fetch(:api_version, V4)]
          raise UnknownApiVersion if active_api.nil?

          # Select encoder
          @encoder = options[:encoder]

          # Set headers
          @headers = {
            'Datadog-Meta-Lang' => 'ruby',
            'Datadog-Meta-Lang-Version' => RUBY_VERSION,
            'Datadog-Meta-Lang-Interpreter' => RUBY_ENGINE,
            'Datadog-Meta-Tracer-Version' => Datadog::VERSION::STRING
          }.merge(options.fetch(:headers, {}))
        end

        def deliver(parcel)
          response = active_api.deliver(service, parcel, encoder: encoder, headers: headers)

          # If API should be downgraded, downgrade and try again.
          if downgrade?(response)
            downgrade!
            response = deliver(parcel)
          end

          response
        end

        def downgrade?(response)
          return false if apis.fallback_from(active_api).nil?
          response.not_found? || response.unsupported?
        end

        def downgrade!
          @active_api = apis.fallback_from(active_api)
          @encoder = active_api.endpoint_for(Transport::Traces::Parcel).encoder
        end

        # Raised when configured with an unknown API version
        class UnknownApiVersion < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No matching transport API for version #{version}!"
          end
        end
      end
    end
  end
end
