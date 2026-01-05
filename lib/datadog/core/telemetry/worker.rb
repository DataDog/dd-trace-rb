# frozen_string_literal: true

require_relative 'event'

require_relative '../utils/only_once_successful'
require_relative '../workers/polling'
require_relative '../workers/queue'

module Datadog
  module Core
    module Telemetry
      # Accumulates events and sends them to the API at a regular interval,
      # including heartbeat event.
      #
      # @api private
      class Worker
        include Core::Workers::Queue
        include Core::Workers::Polling

        DEFAULT_BUFFER_MAX_SIZE = 1000
        APP_STARTED_EVENT_RETRIES = 10

        def initialize(
          heartbeat_interval_seconds:,
          metrics_aggregation_interval_seconds:,
          emitter:,
          metrics_manager:,
          dependency_collection:,
          logger:,
          enabled: true,
          shutdown_timeout: Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT,
          buffer_size: DEFAULT_BUFFER_MAX_SIZE
        )
          @emitter = emitter
          @metrics_manager = metrics_manager
          @dependency_collection = dependency_collection
          @logger = logger

          @ticks_per_heartbeat = (heartbeat_interval_seconds / metrics_aggregation_interval_seconds).to_i
          @current_ticks = 0

          # Workers::Polling settings
          self.enabled = enabled
          # Workers::IntervalLoop settings
          self.loop_base_interval = metrics_aggregation_interval_seconds
          # We actually restart the worker after fork, but this is done
          # via the AtForkMonkeyPatch rather than the worker fork policy
          # because we also need to reset state outside of the worker
          # (e.g. the metrics).
          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_RESTART

          @shutdown_timeout = shutdown_timeout
          @buffer_size = buffer_size

          initialize_state
        end

        # To make the method calls clear, the initialization code is in this
        # method called +initialize_state+ which is called from +after_fork+.
        # This way users of this class (e.g. telemetry Component) do not
        # need to invoke +initialize_state+ directly, which can be confusing.
        private def initialize_state
          self.buffer = buffer_klass.new(@buffer_size)

          @initial_event_once = Utils::OnlyOnceSuccessful.new(APP_STARTED_EVENT_RETRIES)
        end

        attr_reader :logger
        attr_reader :initial_event_once
        attr_reader :initial_event
        attr_reader :emitter

        # Returns true if worker thread is successfully started,
        # false if worker thread was not started but telemetry is enabled,
        # nil if telemetry is disabled.
        def start(initial_event)
          return unless enabled?

          @initial_event = initial_event

          # starts async worker
          # perform should return true if thread was actually started,
          # false otherwise
          perform
        end

        def stop(force_stop = false, timeout = @shutdown_timeout)
          buffer.close if running?

          super
        end

        # Returns true if event was enqueued, nil if not.
        # While returning false may seem more reasonable, the only reason
        # for not enqueueing event (presently) is that telemetry is disabled
        # altogether, and in this case other methods return nil.
        def enqueue(event)
          return unless enabled?

          buffer.push(event)
          true
        end

        def sent_initial_event?
          initial_event_once.success?
        end

        def failed_initial_event?
          initial_event_once.failed?
        end

        def need_initial_event?
          !sent_initial_event? && !failed_initial_event?
        end

        # Wait for the worker to send out all events that have already
        # been queued, up to 15 seconds. Returns whether all events have
        # been flushed.
        #
        # @api private
        def flush(timeout: nil)
          # Increase default timeout to 15 seconds - see the comment in
          # +idle?+ for more details.
          super(timeout: timeout || 15)
        end

        private

        def perform(*events)
          return unless enabled?

          if need_initial_event?
            started!
            unless sent_initial_event?
              # We still haven't succeeded in sending the started event,
              # which will make flush_events do nothing - but the events
              # given to us as the parameter have already been removed
              # from the queue.
              # Put the events back to the front of the queue to not
              # lose them.
              buffer.unshift(*events)
              return
            end
          end

          metric_events = @metrics_manager.flush!
          events = [] if events.nil?
          events += metric_events
          if events.any?
            flush_events(events)
          end

          @current_ticks += 1
          return if @current_ticks < @ticks_per_heartbeat

          @current_ticks = 0
          heartbeat!
        end

        def flush_events(events)
          events = deduplicate_logs(events)

          logger.debug { "Sending #{events&.count} telemetry events" }
          send_event(Event::MessageBatch.new(events))
        end

        def heartbeat!
          return if !enabled? || !sent_initial_event?

          send_event(Event::AppHeartbeat.new)
        end

        def started!
          return unless enabled?

          initial_event_once.run do
            res = send_event(initial_event)

            if res.ok?
              logger.debug { "Telemetry initial event (#{initial_event.type}) is successfully sent" }

              # TODO Dependencies loaded event should probably check for new
              # dependencies and send the new ones.
              # System tests demand only one instance of this event per
              # dependency.
              if @dependency_collection && initial_event.app_started?
                send_event(Event::AppDependenciesLoaded.new)
              end

              true
            else
              logger.debug("Error sending telemetry initial event (#{initial_event.type}), retry after heartbeat interval...")
              false
            end
          end

          if failed_initial_event?
            logger.debug { "Telemetry initial event (#{initial_event.type}) exhausted retries, disabling telemetry worker" }
            disable!
          end
        end

        def send_event(event)
          res = @emitter.request(event)

          disable_on_not_found!(res)

          res
        end

        # This method overrides Queue's dequeue method and does LIFO instead
        # of FIFO that Queue implements. Why?
        def dequeue
          buffer.pop
        end

        def work_pending?
          run_loop? || !buffer.empty?
        end

        def buffer_klass
          if Core::Environment::Ext::RUBY_ENGINE == 'ruby'
            Core::Buffer::CRuby
          else
            Core::Buffer::ThreadSafe
          end
        end

        def disable!
          self.enabled = false
          @metrics_manager.disable!
        end

        def disable_on_not_found!(response)
          return unless response.not_found?

          logger.debug('Agent does not support telemetry; disabling future telemetry events.')
          disable!
        end

        # Call this method in a forked child to reset the state of this worker.
        #
        # Discard any accumulated events since they will be sent by
        # the parent.
        # Discard any accumulated metrics.
        # Restart the worker thread, if it was running in the parent process.
        #
        # This method cannot be called +after_fork+ because workers define
        # and call +after_fork+ which is supposed to do different things.
        def after_fork_monkey_patched
          # If telemetry is disabled, we still reset the state to avoid
          # having wrong state. It is possible that in the future telemetry
          # will be re-enabled after errors.
          initialize_state
          # In the child process, we get a new runtime_id.
          # As such we need to send AppStarted event.
          # In the parent process, the event may have been the
          # SynthAppClientConfigurationChange instead of AppStarted,
          # and in that case we need to convert it to the "regular"
          # AppStarted event.
          if defined?(@initial_event) && @initial_event.is_a?(Event::SynthAppClientConfigurationChange)
            # It would be great to just replace the initial event in
            # +initialize_state+ method. Unfortunately this event requires
            # the entire component tree to build its payload, which we
            # 1) don't currently have in telemetry and
            # 2) don't want to keep a permanent reference to in any case.
            # Therefore we have this +reset!+ method that changes the
            # event type while keeping the payload.
            @initial_event.reset! # steep:ignore NoMethod
          end

          if enabled? && !worker.nil?
            # Start the background thread if it was started in the parent
            # process (which requires telemetry to be enabled).
            # This should be done after all of the state resets.
            perform
          end
        end

        # Deduplicate logs by counting the number of repeated occurrences of the same log
        # entry and replacing them with a single entry with the calculated `count` value.
        # Non-log events are unchanged.
        def deduplicate_logs(events)
          return events if events.empty?

          all_logs = []
          other_events = events.reject do |event|
            if event.is_a?(Event::Log)
              all_logs << event
              true
            else
              false
            end
          end

          return events if all_logs.empty?

          uniq_logs = all_logs.group_by(&:itself).map do |_, logs|
            log = logs.first
            if logs.size > 1
              # New log event with a count of repeated occurrences
              Event::Log.new(message: log.message, level: log.level, stack_trace: log.stack_trace, count: logs.size)
            else
              log
            end
          end

          other_events + uniq_logs
        end

        def idle?
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
          super && sent_initial_event?
        end
      end
    end
  end
end
