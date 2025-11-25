# frozen_string_literal: true

require_relative 'statistics'
require_relative '../../../core/transport/http/client'
require_relative '../../../core/transport/http/env'
require_relative '../../../core/transport/http/response'

module Datadog
  module Tracing
    module Transport
      module HTTP
        # Routes, encodes, and sends tracer data to the trace agent via HTTP.
        class Client < Core::Transport::HTTP::Client
          include Datadog::Tracing::Transport::HTTP::Statistics

          private

          def on_response(response)
            super

            # Update statistics
            update_stats_from_response!(response)
          end

          def on_exception(exception)
            # Note: this method does NOT call super - it has replacement
            # logic for how to log the exception.

            message = build_exception_message(exception)

            if stats.consecutive_errors > 0
              logger.debug(message)
            else
              # Not to report telemetry logs
              logger.error(message)
            end

            # Update statistics
            update_stats_from_exception!(exception)
          end
        end
      end
    end
  end
end
