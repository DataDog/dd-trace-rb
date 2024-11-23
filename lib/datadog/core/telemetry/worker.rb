# frozen_string_literal: true

require_relative 'event'

require_relative '../utils/only_once_successful'
require_relative '../workers/polling'
require_relative '../workers/queue'

module Datadog
  module Core
    module Telemetry
      # Accumulates events and sends them to the API at a regular interval, including heartbeat event.
      class Worker
        include Core::Workers::Queue
        include Core::Workers::Polling

        DEFAULT_BUFFER_MAX_SIZE = 1000
        APP_STARTED_EVENT_RETRIES = 10

        TELEMETRY_STARTED_ONCE = Utils::OnlyOnceSuccessful.new(APP_STARTED_EVENT_RETRIES)

        def initialize(
          heartbeat_interval_seconds:,
          metrics_aggregation_interval_seconds:,
          emitter:,
          metrics_manager:,
          dependency_collection:,
          enabled: true,
          shutdown_timeout: Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT,
          buffer_size: DEFAULT_BUFFER_MAX_SIZE
        )
          @emitter = emitter
          @metrics_manager = metrics_manager
          @dependency_collection = dependency_collection

          @ticks_per_heartbeat = (heartbeat_interval_seconds / metrics_aggregation_interval_seconds).to_i
          @current_ticks = 0

          # Workers::Polling settings
          self.enabled = enabled
          # Workers::IntervalLoop settings
          self.loop_base_interval = metrics_aggregation_interval_seconds
          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_STOP

          @shutdown_timeout = shutdown_timeout
          @buffer_size = buffer_size

          self.buffer = buffer_klass.new(@buffer_size)
        end

        def start
          return if !enabled? || forked?

          # starts async worker
          perform
        end

        def stop(force_stop = false, timeout = @shutdown_timeout)
          buffer.close if running?

          super
        end

        def enqueue(event)
          return if !enabled? || forked?

          buffer.push(event)
        end

        def sent_started_event?
          TELEMETRY_STARTED_ONCE.success?
        end

        def failed_to_start?
          TELEMETRY_STARTED_ONCE.failed?
        end

        private

        def perform(*events)
          return if !enabled? || forked?

          started! unless sent_started_event?

          metric_events = @metrics_manager.flush!
          events = [] if events.nil?
          flush_events(events + metric_events)

          @current_ticks += 1
          return if @current_ticks < @ticks_per_heartbeat

          @current_ticks = 0
          heartbeat!
        end

        def flush_events(events)
          return if events.empty?
          return if !enabled? || !sent_started_event?

          events = deduplicate_logs(events)

          Datadog.logger.debug { "Sending #{events&.count} telemetry events" }
          send_event(Event::MessageBatch.new(events))
        end

        def heartbeat!
          return if !enabled? || !sent_started_event?

          send_event(Event::AppHeartbeat.new)
        end

        def started!
          return unless enabled?

          if failed_to_start?
            Datadog.logger.debug('Telemetry app-started event exhausted retries, disabling telemetry worker')
            disable!
            return
          end

          TELEMETRY_STARTED_ONCE.run do
            res = send_event(Event::AppStarted.new)

            if res.ok?
              Datadog.logger.debug('Telemetry app-started event is successfully sent')

              send_event(Event::AppDependenciesLoaded.new) if @dependency_collection

              true
            else
              Datadog.logger.debug('Error sending telemetry app-started event, retry after heartbeat interval...')
              false
            end
          end
        end

        def send_event(event)
          res = @emitter.request(event)

          disable_on_not_found!(res)

          res
        end

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

          Datadog.logger.debug('Agent does not support telemetry; disabling future telemetry events.')
          disable!
        end

        private

        def deduplicate_logs(events)
          return if events.empty?

          logs = []
          other_events = events.reject do |event|
            if event.is_a?(Event::Log)
              logs << event
              true
            else
              false
            end
          end

          return if logs.empty?

          logs = logs.group_by(&:hash).map do |_, logs|
            log = logs.first
            if logs.size > 1
              Event::Log.new(message: log.message, level: log.level, stack_trace: log.stack_trace, count: logs.size)
            else
              log
            end
          end

          other_events + logs
        end
      end
    end
  end
end
