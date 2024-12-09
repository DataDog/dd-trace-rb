require 'spec_helper'

require 'datadog/core/telemetry/worker'

RSpec.describe Datadog::Core::Telemetry::Worker do
  subject(:worker) do
    described_class.new(
      enabled: enabled,
      heartbeat_interval_seconds: heartbeat_interval_seconds,
      metrics_aggregation_interval_seconds: metrics_aggregation_interval_seconds,
      emitter: emitter,
      metrics_manager: metrics_manager,
      dependency_collection: dependency_collection
    )
  end

  let(:enabled) { true }
  let(:heartbeat_interval_seconds) { 0.5 }
  let(:metrics_aggregation_interval_seconds) { 0.25 }
  let(:metrics_manager) { instance_double(Datadog::Core::Telemetry::MetricsManager, flush!: [], disable!: nil) }
  let(:emitter) { instance_double(Datadog::Core::Telemetry::Emitter) }
  let(:dependency_collection) { false }

  let(:backend_supports_telemetry?) { true }
  let(:response) do
    double(
      Datadog::Core::Telemetry::Http::Adapters::Net::Response,
      not_found?: !backend_supports_telemetry?,
      ok?: backend_supports_telemetry?
    )
  end

  before do
    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:debug).with(any_args)
    allow(Datadog).to receive(:logger).and_return(logger)

    @received_started = false
    @received_heartbeat = false

    allow(emitter).to receive(:request).with(an_instance_of(Datadog::Core::Telemetry::Event::AppStarted)) do
      @received_started = true

      response
    end

    allow(emitter).to receive(:request).with(an_instance_of(Datadog::Core::Telemetry::Event::AppHeartbeat)) do
      @received_heartbeat = true

      response
    end
  end

  after do
    worker.stop(true)
    worker.join

    Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.send(:reset_ran_once_state_for_tests)
  end

  describe '.new' do
    it 'creates a new worker in stopped state' do
      expect(worker).to have_attributes(
        enabled?: true,
        loop_base_interval: metrics_aggregation_interval_seconds,
        run_async?: false,
        running?: false,
        started?: false
      )
    end
  end

  describe '#start' do
    context 'when enabled' do
      context "when backend doesn't support telemetry" do
        let(:backend_supports_telemetry?) { false }

        it 'disables the worker' do
          worker.start

          try_wait_until { !worker.enabled? }

          expect(Datadog.logger).to have_received(:debug).with(
            'Agent does not support telemetry; disabling future telemetry events.'
          )
          expect(@received_started).to be(true)
          expect(@received_heartbeat).to be(false)
        end
      end

      context 'when backend supports telemetry' do
        let(:backend_supports_telemetry?) { true }

        it 'starts the worker and sends heartbeat event' do
          worker.start

          try_wait_until { @received_heartbeat }

          expect(worker).to have_attributes(
            enabled?: true,
            loop_base_interval: metrics_aggregation_interval_seconds,
            run_async?: true,
            running?: true,
            started?: true
          )
        end

        it 'always sends heartbeat event after started event' do
          sent_hearbeat = false
          allow(emitter).to receive(:request).with(kind_of(Datadog::Core::Telemetry::Event::AppHeartbeat)) do
            # app-started was already sent by now
            expect(worker.sent_started_event?).to be(true)

            sent_hearbeat = true

            response
          end

          worker.start

          try_wait_until { sent_hearbeat }
        end

        context 'when app-started event fails' do
          it 'retries' do
            expect(emitter).to receive(:request).with(an_instance_of(Datadog::Core::Telemetry::Event::AppStarted))
              .and_return(
                double(
                  Datadog::Core::Telemetry::Http::Adapters::Net::Response,
                  not_found?: false,
                  ok?: false
                )
              ).once

            expect(emitter).to receive(:request).with(an_instance_of(Datadog::Core::Telemetry::Event::AppStarted)) do
              @received_started = true

              response
            end

            sent_hearbeat = false
            allow(emitter).to receive(:request).with(kind_of(Datadog::Core::Telemetry::Event::AppHeartbeat)) do
              # app-started was already sent by now
              expect(@received_started).to be(true)

              sent_hearbeat = true

              response
            end

            worker.start

            try_wait_until { sent_hearbeat }
          end
        end

        context 'when app-started event exhausted retries' do
          let(:heartbeat_interval_seconds) { 0.1 }
          let(:metrics_aggregation_interval_seconds) { 0.05 }

          it 'stops retrying, never sends heartbeat, and disables worker' do
            expect(emitter).to receive(:request).with(an_instance_of(Datadog::Core::Telemetry::Event::AppStarted))
              .and_return(
                double(
                  Datadog::Core::Telemetry::Http::Adapters::Net::Response,
                  not_found?: false,
                  ok?: false
                )
              ).exactly(described_class::APP_STARTED_EVENT_RETRIES).times

            sent_hearbeat = false
            allow(emitter).to receive(:request).with(kind_of(Datadog::Core::Telemetry::Event::AppHeartbeat)) do
              # app-started was already sent by now
              expect(@received_started).to be(true)

              sent_hearbeat = true

              response
            end

            worker.start

            try_wait_until { !worker.enabled? }

            expect(sent_hearbeat).to be(false)
            expect(worker.failed_to_start?).to be(true)
          end
        end

        context 'when dependencies collection enabled' do
          let(:dependency_collection) { true }

          it 'sends dependencies loaded event after started event' do
            sent_dependencies = false
            allow(emitter).to receive(:request).with(kind_of(Datadog::Core::Telemetry::Event::AppDependenciesLoaded)) do
              # app-started was already sent by now
              # don't use worker.sent_started_event? because it uses the same lock
              expect(@received_started).to be(true)

              sent_dependencies = true

              response
            end

            worker.start

            try_wait_until { sent_dependencies }
          end
        end

        context 'when metrics are flushed' do
          before do
            allow(metrics_manager).to receive(:flush!).and_return(
              [Datadog::Core::Telemetry::Event::GenerateMetrics.new('namespace', [])]
            )
          end

          it 'sends metrics event' do
            received_metrics = false

            allow(emitter).to receive(:request).with(
              an_instance_of(Datadog::Core::Telemetry::Event::MessageBatch)
            ) do |event|
              event.events.each do |subevent|
                received_metrics = true if subevent.is_a?(Datadog::Core::Telemetry::Event::GenerateMetrics)
              end

              response
            end

            worker.start

            try_wait_until { received_metrics }
          end
        end
      end

      context 'when internal error returned by emitter' do
        let(:response) { Datadog::Core::Telemetry::Http::InternalErrorResponse.new('error') }

        it 'does not send heartbeat event' do
          worker.start

          try_wait_until { @received_started }

          expect(@received_heartbeat).to be(false)
        end
      end

      context 'several workers running' do
        it 'sends single started event' do
          started_events = 0
          mutex = Mutex.new
          allow(emitter).to receive(:request).with(kind_of(Datadog::Core::Telemetry::Event::AppStarted)) do
            started_events += 1

            response
          end

          heartbeat_events = 0
          allow(emitter).to receive(:request).with(kind_of(Datadog::Core::Telemetry::Event::AppHeartbeat)) do
            mutex.synchronize do
              heartbeat_events += 1
            end

            response
          end

          workers = Array.new(3) do
            described_class.new(
              enabled: enabled,
              heartbeat_interval_seconds: heartbeat_interval_seconds,
              metrics_aggregation_interval_seconds: metrics_aggregation_interval_seconds,
              emitter: emitter,
              metrics_manager: metrics_manager,
              dependency_collection: dependency_collection
            )
          end
          workers.each(&:start)

          try_wait_until { heartbeat_events >= 3 }

          expect(started_events).to be(1)

          workers.each do |w|
            w.stop(true, 0)
            w.join
          end
        end
      end
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does not start the worker' do
        expect(worker).not_to receive(:perform)

        worker.start
      end
    end
  end

  describe '#stop' do
    let(:heartbeat_interval_seconds) { 60 }
    let(:metrics_aggregation_interval_seconds) { 30 }

    it 'flushes events and stops the worker' do
      worker.start

      try_wait_until { @received_started }

      events_received = 0
      mutex = Mutex.new
      allow(emitter).to receive(:request).with(
        an_instance_of(Datadog::Core::Telemetry::Event::MessageBatch)
      ) do |event|
        event.events.each do |subevent|
          mutex.synchronize do
            events_received += 1 if subevent.is_a?(Datadog::Core::Telemetry::Event::AppIntegrationsChange)
          end
        end

        response
      end

      worker.enqueue(Datadog::Core::Telemetry::Event::AppIntegrationsChange.new)
      worker.stop(true)

      try_wait_until { events_received == 1 }
    end
  end

  describe '#enqueue' do
    it 'adds events to the buffer and flushes them later' do
      events_received = 0
      mutex = Mutex.new
      allow(emitter).to receive(:request).with(
        an_instance_of(Datadog::Core::Telemetry::Event::MessageBatch)
      ) do |event|
        event.events.each do |subevent|
          mutex.synchronize do
            events_received += 1 if subevent.is_a?(Datadog::Core::Telemetry::Event::AppIntegrationsChange)
          end
        end

        response
      end

      worker.start

      events_sent = 3
      events_sent.times do
        worker.enqueue(Datadog::Core::Telemetry::Event::AppIntegrationsChange.new)
      end

      try_wait_until { events_received == events_sent }
    end
  end
end
