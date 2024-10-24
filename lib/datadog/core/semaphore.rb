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
          wake.wait(wake_lock, timeout)
        end
      end

      private

      attr_reader :wake_lock
      attr_reader :wake
    end
  end
end
