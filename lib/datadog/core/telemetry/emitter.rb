# typed: true

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/http/transport'
require 'datadog/core/utils/sequence_numeric'

module Datadog
  module Core
    module Telemetry
      # Class that emits telemetry events
      class Emitter
        attr_reader :http_transport

        # @param sequence [Datadog::Core::Utils::Sequence] Sequence object that stores and increments a counter
        # @param http_transport [Datadog::Core::Telemetry::Http::Transport] Transport object that can be used to send
        #   telemetry requests via the agent
        def initialize(http_transport: Datadog::Core::Telemetry::Http::Transport.new)
          @http_transport = http_transport
        end

        # Retrieves and emits a TelemetryRequest object based on the request type specified
        # @param request_type [String] the type of telemetry request to collect data for
        def request(request_type)
          begin
            request = Datadog::Core::Telemetry::Event.new.telemetry_request(request_type: request_type,
                                                                            seq_id: sequence.next).to_h
            @http_transport.request(request_type: request_type, payload: request.to_json)
          rescue StandardError => e
            Datadog.logger.debug("Unable to send telemetry request for event `#{request_type}`: #{e}")
          end
        end

        # Initializes a SequenceNumeric object to track seq_id if not already initialized; else returns stored
        # SequenceNumeric object
        def sequence
          @sequence ||= Datadog::Core::Utils::SequenceNumeric.new(1)
        end
      end
    end
  end
end
