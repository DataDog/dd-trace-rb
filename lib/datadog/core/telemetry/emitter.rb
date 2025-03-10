# frozen_string_literal: true

require_relative 'request'
require_relative 'http/transport'
require_relative '../utils/sequence'
require_relative '../utils/forking'

module Datadog
  module Core
    module Telemetry
      # Class that emits telemetry events
      class Emitter
        attr_reader :http_transport

        extend Core::Utils::Forking

        # @param http_transport [Datadog::Core::Telemetry::Http::Transport] Transport object that can be used to send
        #   telemetry requests via the agent
        def initialize(http_transport:)
          @http_transport = http_transport
        end

        # Retrieves and emits a TelemetryRequest object based on the request type specified
        def request(event)
          seq_id = self.class.sequence.next
          payload = Request.build_payload(event, seq_id)
          res = @http_transport.request(request_type: event.type, payload: payload.to_json)
          Datadog.logger.debug { "Telemetry sent for event `#{event.type}` (code: #{res.code.inspect})" }
          res
        rescue => e
          Datadog.logger.debug("Unable to send telemetry request for event `#{event.type rescue 'unknown'}`: #{e}")
          Telemetry::Http::InternalErrorResponse.new(e)
        end

        # Initializes a Sequence object to track seq_id if not already initialized; else returns stored
        # Sequence object
        def self.sequence
          after_fork! { @sequence = Datadog::Core::Utils::Sequence.new(1) }
          @sequence ||= Datadog::Core::Utils::Sequence.new(1)
        end
      end
    end
  end
end
