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
          emitter:,
          dependency_collection:,
          enabled: true,
          shutdown_timeout: Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT,
          buffer_size: DEFAULT_BUFFER_MAX_SIZE
        )
          @emitter = emitter
          @dependency_collection = dependency_collection

          # Workers::Polling settings
          self.enabled = enabled
          # Workers::IntervalLoop settings
          self.loop_base_interval = heartbeat_interval_seconds
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

          heartbeat!

          flush_events(events)
        end

        def flush_events(events)
          return if events.nil?
          return if !enabled? || !sent_started_event?

          Datadog.logger.debug { "Sending #{events.count} telemetry events" }
          events.each do |event|
            send_event(event)
          end
        end

        def heartbeat!
          return if !enabled? || !sent_started_event?

          send_event(Event::AppHeartbeat.new)
        end

        def started!
          return unless enabled?

          if failed_to_start?
            Datadog.logger.debug('Telemetry app-started event exhausted retries, disabling telemetry worker')
            self.enabled = false
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
          @run_loop || !buffer.empty?
        end

        def buffer_klass
          if Core::Environment::Ext::RUBY_ENGINE == 'ruby'
            Core::Buffer::CRuby
          else
            Core::Buffer::ThreadSafe
          end
        end

        def disable_on_not_found!(response)
          return unless response.not_found?

          Datadog.logger.debug('Agent does not support telemetry; disabling future telemetry events.')
          self.enabled = false
        end
      end
    end
  end
end
