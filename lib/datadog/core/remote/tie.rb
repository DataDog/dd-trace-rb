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
          remote = Datadog::Core::Remote.active_remote
          return if remote.nil?

          barrier = nil #: Symbol?

          t = Datadog::Core::Utils::Time.measure do
            barrier = remote.barrier(:once)
          end

          Boot.new(barrier, t)
        end
      end
    end
  end
end
