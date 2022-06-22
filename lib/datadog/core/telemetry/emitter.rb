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
          request = collector.telemetry_request(request_type: request_type)
          # send to telemetry API
          res = http_transport.request(request_type: request_type, payload: request)
          increment_seq_id
          res
        end

        def http_transport
          @transporter ||= Telemetry::Http::Transport.new(host: 'instrumentation-telemetry-intake.datad0g.com', port: 443, path: '/api/v2/apmtelemetry')
        end

        def collector
          @collector ||= Telemetry::Event.new
        end

        def increment_seq_id
          collector.seq_id += 1
        end

        def seq_id
          collector.seq_id
        end
      end
    end
  end
end
