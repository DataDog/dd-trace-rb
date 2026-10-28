# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      # Provide Remote Configuration extensions to other components
      module Tie
        # A real class (not a Struct constant) so Steep associates the
        # class with its declaration in the signature.
        class Boot < Struct.new(:barrier, :time)
        end

        def self.boot
          # Hoisted so the nil guard narrows the component for the calls below.
          remote = Datadog::Core::Remote.active_remote
          return if remote.nil?

          # @type var barrier: Symbol?
          barrier = nil

          t = Datadog::Core::Utils::Time.measure do
            barrier = remote.barrier(:once)
          end

          Boot.new(barrier, t)
        end
      end
    end
  end
end
