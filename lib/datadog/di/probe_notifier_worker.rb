# frozen_string_literal: true

require_relative '../core/semaphore'

module Datadog
  module DI
    # Background worker thread for sending probe statuses and snapshots
    # to the backend (via the agent).
    #
    # The loop inside the worker rescues all exceptions to prevent termination
    # due to unhandled exceptions raised by any downstream code.
    # This includes communication and protocol errors when sending the
    # payloads to the agent.
    #
    # The worker groups the data to send into batches. The goal is to perform
    # no more than one network operation per event type per second.
    # There is also a limit on the length of the sending queue to prevent
    # it from growing without bounds if upstream code generates an enormous
    # number of events for some reason.
    #
    # Wake-up events are used (via ConditionVariable) to keep the thread
    # asleep if there is no work to be done.
    #
    # @api private
    class ProbeNotifierWorker
      # Minimum interval between submissions.
      # TODO make this into an internal setting and increase default to 2 or 3.
      MIN_SEND_INTERVAL = 1

      def initialize(settings, transport, logger)
        @settings = settings
        @status_queue = []
        @snapshot_queue = []
        @transport = transport
        @logger = logger
        @lock = Mutex.new
        @wake = Core::Semaphore.new
        @io_in_progress = false
        @sleep_remaining = nil
        @wake_scheduled = false
        @thread = nil
      end

      attr_reader :settings
      attr_reader :logger

      def start
        return if @thread
        @thread = Thread.new do
          loop do
            # TODO If stop is requested, we stop immediately without
            # flushing the submissions. Should we send pending submissions
            # and then quit?
            break if @stop_requested

            sleep_remaining = @lock.synchronize do
              if sleep_remaining && sleep_remaining > 0
                # Recalculate how much sleep time is remaining, then sleep that long.
                set_sleep_remaining
              else
                0
              end
            end

            if sleep_remaining > 0
              # Do not need to update @wake_scheduled here because
              # wake-up is already scheduled for the earliest possible time.
              wake.wait(sleep_remaining)
              next
            end

            begin
              more = maybe_send
            rescue => exc
              raise if settings.dynamic_instrumentation.propagate_all_exceptions

              logger.warn("Error in probe notifier worker: #{exc.class}: #{exc} (at #{exc.backtrace.first})")
            end
            @lock.synchronize do
              @wake_scheduled = more
            end
            wake.wait(more ? MIN_SEND_INTERVAL : nil)
          end
        end
      end

      # Stops the background thread.
      #
      # Attempts a graceful stop with the specified timeout, then falls back
      # to killing the thread using Thread#kill.
      def stop(timeout = 1)
        @stop_requested = true
        wake.signal
        if thread
          unless thread.join(timeout)
            thread.kill
          end
          @thread = nil
        end
      end

      # Waits for background thread to send pending notifications.
      #
      # This method waits for the notification queue to become empty
      # rather than for a particular set of notifications to be sent out,
      # therefore, it should only be called when there is no parallel
      # activity (in another thread) that causes more notifications
      # to be generated.
      def flush
        loop do
          if @thread.nil? || !@thread.alive?
            return
          end

          io_in_progress, queues_empty = @lock.synchronize do
            [io_in_progress?, status_queue.empty? && snapshot_queue.empty?]
          end

          if io_in_progress
            # If we just call Thread.pass we could be in a busy loop -
            # add a sleep.
            sleep 0.25
            next
          elsif queues_empty
            break
          else
            sleep 0.25
            next
          end
        end
      end

      private

      attr_reader :transport
      attr_reader :wake
      attr_reader :thread

      # This method should be called while @lock is held.
      def io_in_progress?
        @io_in_progress
      end

      attr_reader :last_sent

      [
        [:status, 'probe status'],
        [:snapshot, 'snapshot'],
      ].each do |(event_type, event_name)|
        attr_reader "#{event_type}_queue"

        # Adds a status or a snapshot to the queue to be sent to the agent
        # at the next opportunity.
        #
        # If the queue is too large, the event will not be added.
        #
        # Signals the background thread to wake up (and do the sending)
        # if it has been more than 1 second since the last send of the same
        # event type.
        define_method("add_#{event_type}") do |event|
          @lock.synchronize do
            queue = send("#{event_type}_queue")
            # TODO determine a suitable limit via testing/benchmarking
            if queue.length > 100
              logger.warn("#{self.class.name}: dropping #{event_type} because queue is full")
            else
              queue << event
            end
          end

          # Figure out whether to wake up the worker thread.
          # If minimum send interval has elapsed since the last send,
          # wake up immediately.
          @lock.synchronize do
            unless @wake_scheduled
              @wake_scheduled = true
              set_sleep_remaining
              wake.signal
            end
          end
        end

        # Determine how much longer the worker thread should sleep
        # so as not to send in less than MIN_SEND_INTERVAL since the last send.
        # Important: this method must be called when @lock is held.
        #
        # Returns the time remaining to sleep.
        def set_sleep_remaining
          now = Core::Utils::Time.get_time
          @sleep_remaining = if last_sent
            [last_sent + MIN_SEND_INTERVAL - now, 0].max
          else
            0
          end
        end

        public "add_#{event_type}"

        # Sends pending probe statuses or snapshots.
        #
        # This method should ideally only be called when there are actually
        # events to send, but it can be called when there is nothing to do.
        # Currently we only have one wake-up signaling object and two
        # types of events. Therefore on most wake-ups we expect to only
        # send one type of events.
        define_method("maybe_send_#{event_type}") do
          batch = nil
          @lock.synchronize do
            batch = instance_variable_get("@#{event_type}_queue")
            instance_variable_set("@#{event_type}_queue", [])
            @io_in_progress = batch.any? # steep:ignore
          end
          if batch.any? # steep:ignore
            begin
              transport.public_send("send_#{event_type}", batch)
              time = Core::Utils::Time.get_time
              @lock.synchronize do
                @last_sent = time
              end
            rescue => exc
              raise if settings.dynamic_instrumentation.propagate_all_exceptions
              logger.warn("failed to send #{event_name}: #{exc.class}: #{exc} (at #{exc.backtrace.first})")
            end
          end
          batch.any? # steep:ignore
        rescue ThreadError
          # Normally the queue should only be consumed in this method,
          # however if anyone consumes it elsewhere we don't want to block
          # while consuming it here. Rescue ThreadError and return.
          logger.warn("unexpected #{event_name} queue underflow - consumed elsewhere?")
        ensure
          @lock.synchronize do
            @io_in_progress = false
          end
        end
      end

      def maybe_send
        rv = maybe_send_status
        rv || maybe_send_snapshot
      end
    end
  end
end
