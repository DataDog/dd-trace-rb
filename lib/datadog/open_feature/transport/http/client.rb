# frozen_string_literal: true

require_relative '../../../core/transport/http/env'
require_relative '../../../core/transport/http/response'

module Datadog
  module OpenFeature
    module Transport
      module HTTP
        # Routes, encodes, and sends tracer data to the trace agent via HTTP.
        class Client
          attr_reader :api, :logger

          def initialize(api, logger: Datadog.logger)
            @api = api
            @logger = logger
          end

          def send_request(request)
            env = build_env(request)

            yield(api, env)
          rescue => e
            message = "Internal error during request. Cause: #{e.class.name} #{e.message} " \
              "Location: #{Array(e.backtrace).first}"

            logger.debug(message)

            Datadog::Core::Transport::InternalErrorResponse.new(e)
          end

          private

          def build_env(request)
            Datadog::Core::Transport::HTTP::Env.new(request)
          end
        end
      end
    end
  end
end
