require 'ddtrace/transport/http/env'
require 'ddtrace/transport/http/compatibility'

module Datadog
  module Transport
    module HTTP
      # Routes, encodes, and sends tracer data to the trace agent via HTTP.
      class Client
        include Compatibility

        attr_reader \
          :apis,
          :api_id

        def initialize(apis, api_id)
          @apis = apis

          # Activate initial API
          change_api(api_id)
        end

        def deliver(request)
          env = build_env(request)
          response = current_api.call(env)

          # If API should be downgraded, downgrade and try again.
          if downgrade?(response)
            downgrade!
            response = deliver(parcel)
          end

          response
        end

        def build_env(request)
          Env.new(request)
        end

        def downgrade?(response)
          return false unless apis.fallbacks.key?(api_id)
          response.not_found? || response.unsupported?
        end

        def current_api
          apis[api_id]
        end

        def change_api!(api_id)
          raise UnknownApiVersion, api_id unless apis.key?(api_id)
          @api_id = api_id
        end

        def downgrade!
          change_api(apis.fallbacks[api_id])
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
