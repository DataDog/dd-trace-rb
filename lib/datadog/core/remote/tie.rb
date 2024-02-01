# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      # Provide Remote Configuration extensions to other components
      module Tie
        Boot = Struct.new(
          :barrier,
          :time,
        )

        def self.boot
          return if Datadog::Core::Remote.active_remote.nil?

          barrier = nil

          t = Datadog::Core::Utils::Time.measure do
            barrier = Datadog::Core::Remote.active_remote.barrier(:once)
          end

          Boot.new(barrier, t)
        end
      end
    end
  end
end
