# frozen_string_literal: true

module Datadog
  module Profiling
    # Thread-safe helper, used to watch for success vs failure for a background worker thread.
    class WorkerState
      # @rbs @mutex: Thread::Mutex
      # @rbs @condition: Thread::ConditionVariable
      # @rbs @running: bool
      # @rbs @failure: Exception?

      #: () -> void
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @running = false
        @failure = nil
      end

      #: () -> void
      def running!
        @mutex.synchronize do
          @running = true
          @condition.broadcast
        end
      end

      # @rbs failure: Exception
      # @rbs return: void
      def failed!(failure)
        @mutex.synchronize do
          @failure = failure
          @condition.broadcast
        end
      end

      #: () -> void
      def reset!
        @mutex.synchronize do
          @running = false
          @failure = nil
        end
      end

      #: () -> Exception?
      def failure
        @mutex.synchronize { @failure }
      end

      # Waits until the worker runs or fails, and returns its failure, :running, or :not_started on timeout.
      # @rbs timeout_seconds: Integer?
      # @rbs return: Exception | :running | :not_started
      def wait(timeout_seconds)
        @mutex.synchronize do
          @condition.wait(@mutex, timeout_seconds) unless @running || @failure

          failure = @failure
          return failure if failure

          return @running ? :running : :not_started
        end
      end
    end
  end
end
