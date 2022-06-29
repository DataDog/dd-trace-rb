# typed: true

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/http/http_transport'

module Datadog
  module Core
    module Telemetry
      # Module that emits telemetry events
      module Emitter
        module_function

        def request(request_type:)
          begin
            binding.pry
            request = Telemetry::Event.new.telemetry_request(request_type: request_type, seq_id: seq_id).to_h
            request['debug'] = true
            # send to telemetry API
            res = http_transport.request(request_type: request_type, payload: request.to_json)
            increment_seq_id if res.ok?
            res
          rescue StandardError => e
            Datadog.logger.info("Unable to send telemetry request for #{request_type}: #{e}")
          end
        end

        def http_transport
          @transporter ||= Telemetry::Http::Transport.new
        end

        def increment_seq_id
          @seq_id += 1
        end

        def seq_id
          @seq_id ||= 1
        end
      end
    end
  end
end
