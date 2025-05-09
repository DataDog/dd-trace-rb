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
          active_remote = Datadog.send(:components, allow_initialization: false)&.remote
          return if active_remote.nil?

          barrier = nil

          t = Datadog::Core::Utils::Time.measure do
            barrier = active_remote.barrier(:once)
          end

          # steep does not permit the next line due to
          # https://github.com/soutaro/steep/issues/1231
          Boot.new(barrier, t)
        end
      end
    end
  end
end
