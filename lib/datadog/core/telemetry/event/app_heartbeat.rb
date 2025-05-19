module Datadog
  module Core
    module Telemetry
      class Event
        # Telemetry class for the 'app-heartbeat' event
        class AppHeartbeat < Base
          def type
            'app-heartbeat'
          end
        end
      end
    end
  end
end
