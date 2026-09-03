# frozen_string_literal: true

require_relative "base"

module Datadog
  module Core
    module Telemetry
      module Event
        class AppClosing < Base
          def type
            "app-closing"
          end
        end
      end
    end
  end
end
