module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for telemetry API request
            class TelemetryRequest
              attr_reader :api_version, :request_type, :runtime_id, :tracer_time, :seq_id, :payload, :application, :host,
                          :session_id, :debug

              def initialize(api_version:, request_type:, runtime_id:, tracer_time:, seq_id:, payload:, application:, host:,
                             session_id: nil, debug: nil)
                @api_version = api_version
                @request_type = request_type
                @runtime_id = runtime_id
                @tracer_time = tracer_time
                @seq_id = seq_id
                @payload = payload
                @application = application
                @host = host
                @session_id = session_id
                @debug = debug
              end
            end
          end
        end
      end
    end
  end
end
