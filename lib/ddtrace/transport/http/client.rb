require 'ddtrace/transport/http/statistics'
require 'ddtrace/transport/http/env'

module Datadog
  module Transport
    module HTTP
      # Routes, encodes, and sends tracer data to the trace agent via HTTP.
      class Client
        include Transport::HTTP::Statistics

        attr_reader \
          :apis,
          :current_api_id

        def initialize(apis, current_api_id)
          @apis = apis

          # Activate initial API
          change_api!(current_api_id)
        end

        def send_request(request, &block)
          # Build request into env
          env = build_env(request)

          # Get response from API
          response = yield(current_api, env)

          # Update statistics
          update_stats_from_response!(response)

          # If API should be downgraded, downgrade and try again.
          if downgrade?(response)
            downgrade!
            response = send_request(request, &block)
          end

          response
        rescue StandardError => e
          message = "Internal error during HTTP transport request. Cause: #{e.message} Location: #{e.backtrace.first}"

          # Log error
          if stats.consecutive_errors > 0
            Datadog::Logger.log.debug(message)
          else
            Datadog::Logger.log.error(message)
          end

          # Update statistics
          update_stats_from_exception!(e)

          InternalErrorResponse.new(e)
        end

        def build_env(request)
          Env.new(request)
        end

        def downgrade?(response)
          return false unless apis.fallbacks.key?(current_api_id)
          response.not_found? || response.unsupported?
        end

        def current_api
          apis[current_api_id]
        end

        def change_api!(api_id)
          raise UnknownApiVersionError, api_id unless apis.key?(api_id)
          @current_api_id = api_id
        end

        def downgrade!
          downgrade_api_id = apis.fallbacks[current_api_id]
          raise NoDowngradeAvailableError, current_api_id if downgrade_api_id.nil?
          change_api!(downgrade_api_id)
        end

        # Raised when configured with an unknown API version
        class UnknownApiVersionError < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No matching transport API for version #{version}!"
          end
        end

        # Raised when configured with an unknown API version
        class NoDowngradeAvailableError < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No downgrade from transport API version #{version} is available!"
          end
        end
      end
    end
  end
end
