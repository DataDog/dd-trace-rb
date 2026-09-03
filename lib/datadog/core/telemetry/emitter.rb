# frozen_string_literal: true

require_relative "request"
require_relative "../transport/response"
require_relative "../utils/sequence"
require_relative "../utils/forking"

module Datadog
  module Core
    module Telemetry
      class Emitter
        attr_reader :transport, :logger

        extend Core::Utils::Forking

        def initialize(transport, logger: Datadog.logger, debug: false)
          @transport = transport
          @logger = logger
          @debug = !!debug
        end

        def debug?
          @debug
        end

        def request(event)
          seq_id = self.class.sequence.next
          payload = Request.build_payload(event, seq_id, debug: debug?)
          res = @transport.send_telemetry(request_type: event.type, payload: payload)
          if res.ok?
            logger.debug { "Telemetry sent for event `#{event.type}`" }
          else
            logger.debug { "Failed to send telemetry for event `#{event.type}`: #{res.inspect}" }
          end
          res
        rescue => e
          logger.debug {
            "Unable to send telemetry request for event `#{event.respond_to?(:type) ? event.type : event.to_s}`: #{e.class}: #{e.message}"
          }
          Core::Transport::InternalErrorResponse.new(e)
        end

        def self.sequence
          after_fork! { @sequence = Datadog::Core::Utils::Sequence.new(1) }
          @sequence ||= Datadog::Core::Utils::Sequence.new(1)
        end
      end
    end
  end
end
