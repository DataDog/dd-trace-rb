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

        # Returned when boot has already been performed for the current remote
        # component in this process. barrier == :pass tells Tie::Tracing.tag
        # not to set per-request boot timing metrics on subsequent spans.
        PASS = Boot.new(:pass, 0.0)

        @mutex = Mutex.new
        @booted_in_pid = nil
        @booted_remote_id = nil

        # Boot the Remote Configuration worker for this process.
        #
        # Idempotent: only the first call per (process, remote component) pair
        # actually waits on `barrier(:once)`. Subsequent calls return PASS so
        # that Tie::Tracing.tag skips per-request boot metrics.
        #
        # The cache is keyed on both `Process.pid` and the remote component's
        # `object_id` so that:
        #   - A fork (new pid) triggers a fresh boot in the child.
        #   - A new `Datadog.configure` call (new remote component) triggers a
        #     fresh boot for the replacement component.
        def self.boot
          return if Datadog::Core::Remote.active_remote.nil?

          active = Datadog::Core::Remote.active_remote

          @mutex.synchronize do
            if @booted_in_pid == Process.pid && @booted_remote_id == active.object_id
              return PASS
            end

            barrier = nil
            t = Datadog::Core::Utils::Time.measure do
              barrier = active.barrier(:once)
            end

            @booted_in_pid = Process.pid
            @booted_remote_id = active.object_id

            # steep does not permit the next line due to
            # https://github.com/soutaro/steep/issues/1231
            Boot.new(barrier, t)
          end
        end

        # Test helper. Resets the per-process boot cache.
        # @!visibility private
        def self.reset_for_tests!
          @mutex.synchronize do
            @booted_in_pid = nil
            @booted_remote_id = nil
          end
        end
        private_class_method :reset_for_tests!
      end
    end
  end
end
