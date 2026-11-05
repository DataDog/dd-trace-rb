# frozen_string_literal: true

require_relative "../telemetry"

module Datadog
  module Tracing
    module Transport
      module Native
        class Telemetry < Datadog::Tracing::Transport::Telemetry
          def initialize(client)
            super(client, source: "libdatadog")
          end
        end
      end
    end
  end
end
