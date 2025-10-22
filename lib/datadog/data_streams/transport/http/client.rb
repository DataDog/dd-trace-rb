# frozen_string_literal: true

require_relative '../../../core/transport/http/response'

module Datadog
  module DataStreams
    module Transport
      module HTTP
        # HTTP client for Data Streams Monitoring
        class Client
          attr_reader :api, :logger

          def initialize(api, logger: Datadog.logger)
            @api = api
            @logger = logger
          end

          def send_stats_payload(request)
            send_request(request) do |api, env|
              api.send_stats(env)
            end
          end

          private

          def send_request(request, &block)
            # Build request into env
            env = build_env(request)

            # Get response from API
            response = yield(api, env)

            response
          rescue => e
            message =
              "Internal error during #{self.class.name} request. Cause: #{e.class.name} #{e.message} " \
                "Location: #{Array(e.backtrace).first}"

            logger.debug(message)

            Datadog::Core::Transport::InternalErrorResponse.new(e)
          end

          def build_env(request)
            Datadog::Core::Transport::HTTP::Env.new(request)
          end
        end
      end
    end
  end
end

