# frozen_string_literal: true

module Datadog
  module Core
    module Workers
      # Adds queue behavior to workers, with a buffer
      # to which items can be queued then dequeued.
      #
      # This module is included in some but not all workers.
      # Notably, Data Streams Processor uses a queue but implements it
      # inline rather than using this module.
      #
      # The workers that do include Queue also include Polling, which
      # in turn includes Async::Thread and IntervalLoop. This means
      # we have e.g. +in_iteration?+ always available in any worker
      # that includes Queue.
      #
      # @api private
      module Queue
        def self.included(base)
          base.prepend(PrependedMethods)
        end

        # Methods that must be prepended
        module PrependedMethods
          def perform(*args)
            if work_pending?
              work = dequeue
              super(*work)
            end
          end
        end

        def buffer
          # Why is this an unsynchronized Array and not a Core::Buffer
          # instance?
          @buffer ||= []
        end

        def enqueue(*args)
          buffer.push(args)
        end

        def dequeue
          buffer.shift
        end

        # Are there more items to be processed next?
        def work_pending?
          !buffer.empty?
        end

        # Wait for the worker to finish handling all work that has already
        # been submitted to it.
        #
        # If the worker is not enabled, returns nil.
        # If the worker is enabled, returns whether, at the point of return,
        # there was no pending or in progress work.
        #
        # Flushing can time out because there is a constant stream of work
        # submitted at the same or higher rate than it is processed.
        # Flushing can also fail if the worker thread is not running -
        # this method will not flush from the calling thread.
        def flush(timeout: nil)
          # Default timeout is 5 seconds.
          # Specific workers can override it to be more or less
          timeout ||= 5

          # Nothing needs to be done if the worker is not enabled.
          return nil unless enabled?

          unless running?
            unless buffer.empty?
              # If we are asked to flush but the worker is not running,
              # do not flush from the caller thread. If the buffer is not
              # empty, it will not be flushed. Log a warning to this effect.
              #
              # We are not guaranteed to have a logger as an instance method,
              # reference the global for now - all other worker methods
              # also reference the logger globally.
              # TODO inject it into worker instances.
              Datadog.logger.debug { "Asked to flush #{self} when the worker is not running" }
              return false
            end
          end

          started = Utils::Time.get_time
          loop do
            # The AppStarted event is triggered by the worker itself,
            # from the worker thread. As such the main thread has no way
            # to delay itself until that event is queued and we need some
            # way to wait until that event is sent out to assert on it in
            # the test suite. Check the run once flag which *should*
            # indicate the event has been queued (at which point our queue
            # depth check should wait until it's sent).
            # This is still a hack because the flag can be overridden
            # either way with or without the event being sent out.
            # Note that if the AppStarted sending fails, this check
            # will return false and flushing will be blocked until the
            # 15 second timeout.
            # Note that the first wait interval between telemetry event
            # sending is 10 seconds, the timeout needs to be strictly
            # greater than that.
            return true if idle?

            return false if Utils::Time.get_time - started > timeout
            p ['flushing',buffer.empty?,buffer,in_iteration?]

            sleep 0.5
          end
        end

        protected

        attr_writer \
          :buffer

        # Returns whether this worker has no pending work and is not actively
        # working.
        #
        # The reason why "actively working" is considered is that we use
        # flushing to ensure all work is completed before asserting on the
        # outcome in the tests - if work is happening in a background thread,
        # it's too early to assert on its results.
        def idle?
          # We have a +work_pending?+ method in this class that semantically
          # would be appropriate here instead of calling +buffer.empty?+.
          # Unfortunately IntervalLoop replaces our implementation of
          # +work_pending?+ with one that doesn't make sense at least for the
          # Queue. And we can't change the order of module includes because
          # they all override +perform+ and the correct behavior depends on
          # placing IntervalLoop after Queue.
          #
          # The TraceWriter worker then defines +work_pending?+ to be the
          # same as Queue implementation here... Essentially, it demands
          # the behavior that perhaps should be applied to all workers.
          #
          # Until this mess is untangled, call +buffer.empty?+ here.
          buffer.empty? && !in_iteration?
        end
      end
    end
  end
end
