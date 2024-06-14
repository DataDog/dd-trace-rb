# frozen_string_literal: true

require_relative 'event'

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

        def initialize(
          heartbeat_interval_seconds:,
          emitter:,
          enabled: true,
          shutdown_timeout: Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT,
          buffer_size: DEFAULT_BUFFER_MAX_SIZE
        )
          @emitter = emitter

          @sent_started_event = false

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
          buffer.push(event)
        end

        def sent_started_event?
          @sent_started_event
        end

        private

        def perform(*events)
          return if !enabled? || forked?

          started! unless sent_started_event?

          heartbeat!

          flush_events(events)
        end

        def flush_events(events)
          return if !enabled? || !sent_started_event?

          Datadog.logger.debug { "Sending #{events&.count} telemetry events" }
          (events || []).each do |event|
            send_event(event)
          end
        end

        def heartbeat!
          return if !enabled? || !sent_started_event?

          send_event(Event::AppHeartbeat.new)
        end

        def started!
          return unless enabled?

          res = send_event(Event::AppStarted.new)

          if res.not_found? # Telemetry is only supported by agent versions 7.34 and up
            Datadog.logger.debug('Agent does not support telemetry; disabling future telemetry events.')
            self.enabled = false
          end

          if res.ok?
            Datadog.logger.debug('Telemetry app-started event is successfully sent')
            @sent_started_event = true
          end
        end

        def send_event(event)
          Datadog.logger.debug { "Sending telemetry event: #{event}" }
          response = @emitter.request(event)
          Datadog.logger.debug { "Received response: #{response}" }
          response
        end

        def dequeue
          buffer.pop
        end

        def buffer_klass
          if Core::Environment::Ext::RUBY_ENGINE == 'ruby'
            Core::Buffer::CRuby
          else
            Core::Buffer::ThreadSafe
          end
        end
      end
    end
  end
end
