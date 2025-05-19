module Datadog
  module Core
    module Telemetry
      class Event
        # Telemetry class for the 'app-closing' event
        class AppClosing < Base
          def type
            'app-closing'
          end
        end
      end
    end
  end
end
