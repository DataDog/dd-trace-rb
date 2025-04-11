# frozen_string_literal: true

require_relative 'request'
require_relative 'http/transport'
require_relative '../transport/response'
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
        def initialize(http_transport:, api_key:)
          @http_transport = http_transport
          # TODO api_key should be part of transport
          @api_key = api_key
        end

        attr_reader :api_key

        # Retrieves and emits a TelemetryRequest object based on the request type specified
        def request(event)
          seq_id = self.class.sequence.next
          payload = Request.build_payload(event, seq_id)
          res = @http_transport.send_telemetry(request_type: event.type, payload: payload, api_key: api_key)
          Datadog.logger.debug { "Telemetry sent for event `#{event.type}` (response: #{res})" }
          res
        rescue => e
          Datadog.logger.debug("Unable to send telemetry request for event `#{event.type rescue 'unknown'}`: #{e}")
          Core::Transport::InternalErrorResponse.new(e)
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
