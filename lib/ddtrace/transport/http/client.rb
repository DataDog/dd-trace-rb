require 'ddtrace/transport/statistics'
require 'ddtrace/transport/http/env'

module Datadog
  module Transport
    module HTTP
      # Routes, encodes, and sends tracer data to the trace agent via HTTP.
      class Client
        include Transport::Statistics

        attr_reader :api

        def initialize(api)
          @api = api
        end

        def send_request(request, &block)
          # Build request into env
          env = build_env(request)

          # Get responses from API
          response = yield(api, env)

          # Update statistics
          update_stats_from_response!(response)

          response
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
      end
    end
  end
end
