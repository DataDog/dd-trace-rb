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

        @mutex = Mutex.new
        @booted_in_pid = nil
        @last_boot = nil

        # Boot the Remote Configuration worker for this process.
        #
        # Idempotent: only the first call per process actually waits on
        # `barrier(:once)`. Subsequent calls return the cached `Boot` struct.
        # After a fork, `Process.pid` changes, which invalidates the cache and
        # the next call boots again in the child.
        def self.boot
          return if Datadog::Core::Remote.active_remote.nil?

          @mutex.synchronize do
            return @last_boot if @booted_in_pid == Process.pid

            barrier = nil
            t = Datadog::Core::Utils::Time.measure do
              barrier = Datadog::Core::Remote.active_remote.barrier(:once)
            end

            # steep does not permit the next line due to
            # https://github.com/soutaro/steep/issues/1231
            @last_boot = Boot.new(barrier, t)
            @booted_in_pid = Process.pid
            @last_boot
          end
        end

        # Test helper. Resets the per-process boot cache.
        # @!visibility private
        def self.reset_for_tests!
          @mutex.synchronize do
            @booted_in_pid = nil
            @last_boot = nil
          end
        end
        private_class_method :reset_for_tests!
      end
    end
  end
end
