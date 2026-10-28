# frozen_string_literal: true

module Datadog
  module Core
    # Semaphore pattern implementation, as described in documentation for
    # ConditionVariable.
    #
    # @api private
    class Semaphore
      def initialize
        @wake_lock = Mutex.new
        @wake = ConditionVariable.new
      end

      def signal
        wake_lock.synchronize do
          wake.signal
        end
      end

      def wait(timeout = nil)
        wake_lock.synchronize do
          # ConditionVariable#wait accepts Numeric seconds at runtime; the
          # bundled core signatures only model the Timeouts module form.
          wake.wait(wake_lock, timeout) # steep:ignore ArgumentTypeMismatch
        end
      end

      private

      attr_reader :wake_lock, :wake
    end
  end
end
