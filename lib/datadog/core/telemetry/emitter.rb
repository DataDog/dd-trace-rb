# typed: true

require 'datadog/core/telemetry/event'

module Datadog
  module Core
    module Telemetry
      # Module that emits telemetry events
      module Emitter
        module_function

        def request(request_type:)
          request = collector.telemetry_request(request_type: request_type)
          # send to telemetry API
          increment_seq_id
          request
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
