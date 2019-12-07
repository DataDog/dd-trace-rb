module Datadog
  module Workers
    # Adds looping behavior to workers, with a sleep
    # interval between each loop.
    module IntervalLoop
      BACK_OFF_RATIO = 1.2
      BACK_OFF_MAX = 5
      DEFAULT_INTERVAL = 1

      def self.included(base)
        base.send(:prepend, PrependedMethods)
      end

      # Methods that must be prepended
      module PrependedMethods
        def perform(*args)
          perform_loop { super(*args) }
        end
      end

      def stop_loop
        mutex.synchronize do
          return false unless run_loop?
          @run_loop = false
          shutdown.signal
        end

        true
      end

      def work_pending?
        run_loop?
      end

      def run_loop?
        @run_loop = false unless instance_variable_defined?(:@run_loop)
        @run_loop == true
      end

      def loop_default_interval
        @loop_default_interval ||= DEFAULT_INTERVAL
      end

      def loop_back_off_ratio
        @loop_back_off_ratio ||= BACK_OFF_RATIO
      end

      def loop_back_off_max
        @loop_back_off_max ||= BACK_OFF_MAX
      end

      def loop_wait_time
        @loop_wait_time ||= loop_default_interval
      end

      def loop_back_off?
        false
      end

      def loop_back_off!(amount = nil)
        @loop_wait_time = amount || [loop_wait_time * BACK_OFF_RATIO, BACK_OFF_MAX].min
      end

      protected

      attr_writer \
        :loop_back_off_max,
        :loop_back_off_ratio,
        :loop_default_interval

      def mutex
        @mutex ||= Mutex.new
      end

      private

      def perform_loop
        @run_loop = true

        loop do
          if work_pending?
            # Run the task
            yield

            # Reset the wait interval
            loop_back_off!(loop_default_interval)
          elsif loop_back_off?
            # Back off the wait interval a bit
            loop_back_off!
          end

          # Wait for an interval, unless shutdown has been signaled.
          mutex.synchronize do
            return unless run_loop? || work_pending?
            shutdown.wait(mutex, loop_wait_time) if run_loop?
          end
        end
      end

      def shutdown
        @shutdown ||= ConditionVariable.new
      end
    end
  end
end
