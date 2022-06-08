module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for telemetry API request
            class TelemetryRequest
              attr_reader \
                :api_version,
                :application,
                :debug,
                :host,
                :payload,
                :request_type,
                :runtime_id,
                :seq_id,
                :session_id,
                :tracer_time

              def initialize(api_version:, application:, host:, payload:, request_type:, runtime_id:, seq_id:, tracer_time:,
                             debug: nil, session_id: nil)
                @api_version = api_version
                @application = application
                @debug = debug
                @host = host
                @payload = payload
                @request_type = request_type
                @runtime_id = runtime_id
                @seq_id = seq_id
                @session_id = session_id
                @tracer_time = tracer_time
              end
            end
          end
        end
      end
    end
  end
end
