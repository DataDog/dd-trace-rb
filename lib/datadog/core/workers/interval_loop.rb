# frozen_string_literal: true

module Datadog
  module Core
    module Workers
      # Adds looping behavior to workers, with a sleep
      # interval between each loop.
      #
      # This module is included in Polling module, and has no other
      # direct users.
      #
      # @api private
      module IntervalLoop
        BACK_OFF_RATIO = 1.2
        BACK_OFF_MAX = 5
        BASE_INTERVAL = 1

        # This single shared mutex is used to avoid concurrency issues during the
        # initialization of per-instance lazy-initialized mutexes.
        MUTEX_INIT = Mutex.new

        def self.included(base)
          base.prepend(PrependedMethods)
        end

        # Methods that must be prepended
        module PrependedMethods
          def perform(*args)
            perform_loop do
              @in_iteration = true
              begin
                super(*args)
              ensure
                @in_iteration = false
              end
            end
          end

          def in_iteration?
            defined?(@in_iteration) && @in_iteration
          end
        end

        def stop_loop
          mutex.synchronize do
            # Do not call run_loop? from this method to see if the loop
            # is running, because @run_loop is normally initialized by
            # the background thread and if the stop is requested right
            # after the worker starts, the background thread may be created
            # (and scheduled) but hasn't run yet, thus skipping the
            # write to @run_loop here would leave the thread running forever.
            @run_loop = false

            # It is possible that we don't need to signal shutdown if
            # @run_loop was not initialized (i.e. we changed it from not
            # defined to false above). But let's be safe and signal the
            # shutdown anyway, I don't see what harm it can cause.
            shutdown.signal
          end

          # Previously, this method would return false (and do nothing)
          # if the worker was not running the loop. However, this was racy -
          # see https://github.com/DataDog/ruby-guild/issues/279.
          # stop_loop now always sets the state to "stop requested" and,
          # correspondingly, always returns true.
          #
          # There is some test code that returns false when mocking this
          # method - most likely this method should be treated as a void one
          # and the caller should assume that the stop was always requested.
          true
        end

        # TODO This overwrites Queue's +work_pending?+ method with an
        # implementation that, to me, is at leat questionable semantically:
        # the Queue's idea of pending work is if the buffer is not empty,
        # but this module says that work is pending if the work processing
        # loop is scheduled to run (in other words, as long as the background
        # thread is running, there is always pending work).
        def work_pending?
          run_loop?
        end

        def run_loop?
          return false unless instance_variable_defined?(:@run_loop)

          @run_loop == true
        end

        def loop_base_interval
          @loop_base_interval ||= BASE_INTERVAL
        end

        def loop_back_off_ratio
          @loop_back_off_ratio ||= BACK_OFF_RATIO
        end

        def loop_back_off_max
          @loop_back_off_max ||= BACK_OFF_MAX
        end

        def loop_wait_time
          @loop_wait_time ||= loop_base_interval
        end

        def loop_wait_time=(value)
          @loop_wait_time = value
        end

        def loop_back_off!
          self.loop_wait_time = [loop_wait_time * BACK_OFF_RATIO, BACK_OFF_MAX].min
        end

        # Should perform_loop just straight into work, or start by waiting?
        #
        # The use case is if we want to report some information (like profiles) from time to time, we may not want to
        # report empty/zero/some residual value immediately when the worker starts.
        def loop_wait_before_first_iteration?
          false
        end

        protected

        attr_writer \
          :loop_back_off_max,
          :loop_back_off_ratio,
          :loop_base_interval

        def mutex
          @mutex || MUTEX_INIT.synchronize { @mutex ||= Mutex.new }
        end

        private

        def perform_loop
          mutex.synchronize do
            unless defined?(@run_loop)
              # This write must only happen if @run_loop is not defined
              # (i.e., not initialized). In the case when the worker is
              # asked to stop right after it is created, the thread may not
              # have run yet by the time +stop_loop+ is invoked and
              # we need to preserve the stop-requested state from
              # +stop_loop+ to +perform_loop+.
              #
              # If the workers are refactored to use classes and inheritance
              # and their state, such as @run_loop, is initialized in
              # constructors, the write can be made unconditional.
              @run_loop = true
            end

            shutdown.wait(mutex, loop_wait_time) if loop_wait_before_first_iteration?
          end

          loop do
            if work_pending?
              # There's work to do...
              # Run the task
              yield
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
end
