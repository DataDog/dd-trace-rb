# frozen_string_literal: true

require_relative 'env'
require_relative '../response'

module Datadog
  module Core
    module Transport
      module HTTP
        # Routes, encodes, and sends DI data to the trace agent via HTTP.
        #
        # @api private
        class Client
          attr_reader :api, :logger

          def initialize(api, logger:)
            @api = api
            @logger = logger
          end

          private

          def send_request(request, &block)
            # Build request into env
            env = build_env(request)

            # Get responses from API
            yield(api, env).tap do |response|
              on_response(response)
            end
          rescue => exception
            on_exception(exception)

            Datadog::Core::Transport::InternalErrorResponse.new(exception)
          end

          def build_env(request)
            Datadog::Core::Transport::HTTP::Env.new(request)
          end

          # Callback that is invoked if a request did not raise an exception
          # (but did not necessarily complete successfully).
          #
          # Override in subclasses.
          #
          # Note that the client will return the original response -
          # the return value of this method is ignored, and response should
          # not be modified.
          def on_response(response)
          end

          # Callback that is invoked if a request failed with an exception.
          #
          # Override in subclasses.
          def on_exception(exception)
            message = build_exception_message(exception)

            logger.debug(message)
          end

          def build_exception_message(exception)
            "Internal error during #{self.class.name} request. Cause: #{exception.class}: #{exception} " \
              "Location: #{Array(exception.backtrace).first}"
          end
        end
      end
    end
  end
end
