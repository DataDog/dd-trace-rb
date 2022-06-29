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
          request = Telemetry::Event.new.telemetry_request(request_type: request_type, seq_id: seq_id).to_h
          request['debug'] = true
          # send to telemetry API
          res = http_transport.request(request_type: request_type, payload: request.to_json)
          if res.ok?
            increment_seq_id
          end
          res
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
