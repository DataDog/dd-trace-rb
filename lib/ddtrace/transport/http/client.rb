require 'ddtrace/transport/statistics'
require 'ddtrace/transport/http/env'

module Datadog
  module Transport
    module HTTP
      # Routes, encodes, and sends tracer data to the trace agent via HTTP.
      class Client
        include Transport::Statistics

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

          # Get responses from API
          responses = yield(current_api, env)

          # Update statistics
          responses.each { |r| update_stats_from_response!(r) }

          # If API should be downgraded, downgrade and try again.
          if responses.find { |r| downgrade?(r) }
            downgrade!
            responses = send_request(request, &block)
          end

          responses
        rescue StandardError => e
          message = "Internal error during HTTP transport request. Cause: #{e.message} Location: #{e.backtrace.first}"

          # Log error
          if stats.consecutive_errors > 0
            Datadog::Tracer.log.debug(message)
          else
            Datadog::Tracer.log.error(message)
          end

          # Update statistics
          stats.internal_error += 1
          stats.consecutive_errors += 1

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
