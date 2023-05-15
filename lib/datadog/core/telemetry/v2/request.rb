# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      module V2
        # Base request object for Telemetry V2.
        class Request
          def initialize(request_type)
            @request_type = request_type
          end

          def to_h
            {
              request_type: @request_type
            }
          end
        end
      end
    end
  end
end
