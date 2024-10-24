# frozen_string_literal: true

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
      def initialize(settings, agent_settings, transport)
        @settings = settings
        @status_queue = []
        @snapshot_queue = []
        @transport = transport
        @lock = Mutex.new
        @wake_lock = Mutex.new
        @wake = ConditionVariable.new
        @io_in_progress = false
      end

      attr_reader :settings

      def start
        return if defined?(@thread) && @thread
        @thread = Thread.new do
          loop do
            break if @stop_requested
            begin
              if maybe_send
                # Run next iteration immediately in case more work is
                # in the queue
              end
            rescue NoMemoryError, SystemExit, Interrupt
              raise
            rescue => exc
              raise if settings.dynamic_instrumentation.propagate_all_exceptions

              warn "Error in probe notifier worker: #{exc.class}: #{exc} (at #{exc.backtrace.first})"
            end
            wake_lock.synchronize do
              wake.wait(wake_lock, 1)
            end
          end
        end
      end

      # Stops the background thread.
      #
      # Attempts a graceful stop with the specified timeout, then falls back
      # to killing the thread using Thread#kill.
      def stop(timeout = 1)
        @stop_requested = true
        wake_lock.synchronize do
          wake.signal
        end
        unless thread&.join(timeout)
          thread.kill
        end
        @thread = nil
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
      attr_reader :wake_lock
      attr_reader :thread

      # This method should be called while @lock is held.
      def io_in_progress?
        @io_in_progress
      end

      [
        [:status, 'probe status'],
        [:snapshot, 'snapshot'],
      ].each do |(event_type, event_name)|
        attr_reader "#{event_type}_queue"
        attr_reader "last_#{event_type}_sent"

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
              # TODO use datadog logger
              warn "dropping #{event_type} because queue is full"
            else
              queue << event
            end
          end
          last_sent = @lock.synchronize do
            send("last_#{event_type}_sent")
          end
          if last_sent
            now = Core::Utils::Time.get_time
            if now - last_sent > 1
              wake_lock.synchronize do
                wake.signal
              end
            end
          else
            # First time sending
            wake_lock.synchronize do
              wake.signal
            end
          end
        end

        public "add_#{event_type}"

        # Sends pending probe statuses or snapshots.
        #
        # This method should ideallyy only be called when there are actually
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
                instance_variable_set("@last_#{event_type}_sent", time)
              end
            rescue => exc
              raise if settings.dynamic_instrumentation.propagate_all_exceptions
              # TODO log to logger
              puts "failed to send #{event_name}: #{exc.class}: #{exc} (at #{exc.backtrace.first})"
            end
          end
          batch.any? # steep:ignore
        rescue ThreadError
          # Normally the queue should only be consumed in this method,
          # however if anyone consumes it elsewhere we don't want to block
          # while consuming it here. Rescue ThreadError and return.
          warn "unexpected #{event_name} queue underflow - consumed elsewhere?"
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
