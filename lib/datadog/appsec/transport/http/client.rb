# typed: true

require_relative '../../../../ddtrace/transport/http/env'

module Datadog
  module AppSec
    module Transport
      module HTTP
        # Routes, encodes, and sends tracer data to the trace agent via HTTP.
        class Client
          attr_reader :api

          def initialize(api)
            @api = api
          end

          def send_request(request, &block)
            # Build request into env
            env = build_env(request)

            # Get responses from API
            response = yield(api, env)

            response
          rescue StandardError => e
            message =
              "Internal error during #{self.class.name} request. Cause: #{e.class.name} #{e.message} " \
              "Location: #{Array(e.backtrace).first}"

            Datadog::Transport::InternalErrorResponse.new(e)
          end

          def build_env(request)
            Datadog::Transport::HTTP::Env.new(request)
          end
        end
      end
    end
  end
end
