require 'spec_helper'

RSpec.describe Datadog::Core::Telemetry::Component do
  forking_platform_only

  before(:all) do
    reset_at_fork_monkey_patch_for_components!
  end

  let(:sent_payloads) { [] }

  let(:handler_proc) do
    lambda do |req, _res|
      expect(req.content_type).to eq('application/json')
      payload = JSON.parse(req.body)
      sent_payloads << {
        headers: req.header,
        payload: payload,
      }
    end
  end

  http_server do |http_server|
    http_server.mount_proc('/telemetry/proxy/api/v2/apmtelemetry', &handler_proc)
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.telemetry.enabled = true
      # Host may be overridden by environment variables
      settings.agent.host = 'localhost'
      settings.agent.port = http_server_port
      # In this test we want to assert on dependency events
      settings.telemetry.dependency_collection = true
      # In CI tests can take a long time to run, avoid extra heartbeat events
      settings.telemetry.heartbeat_interval_seconds = 1_000
    end
  end

  let(:logger) { logger_allowing_debug }

  # Uncomment for debugging to see the log entries.
  #let(:logger) { Logger.new(STDERR) }

  let(:components) do
    Datadog::Core::Configuration::Components.new(settings)
  end

  let(:component) do
    components.telemetry
  end

  let(:agent_settings) do
    components.agent_settings
  end

  after do
    component.shutdown!
  end

  let(:initial_event) do
    double(Datadog::Core::Telemetry::Event::AppStarted,
      payload: {hello: 'world'},
      type: 'app-started',
      app_started?: true,)
  end

  let(:response) do
    double(Datadog::Core::Transport::HTTP::Response,
      ok?: true,)
  end

  context 'when telemetry is disabled' do
    before do
      settings.telemetry.enabled = false
    end

    it 'stays disabled in child process' do
      expect(component.enabled?).to be false
      expect(component.worker).to be nil

      expect_in_fork do
        expect(component.enabled?).to be false
        expect(component.worker).to be nil
      end
    end
  end

  context 'when telemetry is enabled' do
    before do
      settings.telemetry.enabled = true
    end

    before do
      # after_fork handler goes through the global variable.
      #
      # Cannot use +expect+ here because the call is in child process.
      allow(Datadog).to receive(:components).and_return(components)
    end

    it 'stays enabled in child process' do
      expect(component.enabled?).to be true
      expect(component.worker).to be_a(Datadog::Core::Telemetry::Worker)
      expect(component.worker.enabled?).to be true

      expect_in_fork do
        expect(component.enabled?).to be true
        expect(component.worker.enabled?).to be true
      end
    end

    context 'when worker is running' do
      before do
        # Reduce interval between event submissions in worker
        # to make the test run faster.
        # Using +expect+ instead of +allow+ here has failed in CI,
        # presumably because it is possible for all of the payloads
        # to be sent out "immediately" and not require any waiting.
        allow(component.worker).to receive(:loop_wait_time).and_return(1)
      end

      before do
        component.worker.start(initial_event)
      end

      it 'restarts worker after fork' do
        skip 'flaky on Ruby 2.5 (APMLP-931)' if RUBY_VERSION.start_with?('2.5.')

        expect(component.enabled?).to be true
        expect(component.worker).to be_a(Datadog::Core::Telemetry::Worker)
        expect(component.worker.enabled?).to be true
        expect(component.worker.running?).to be true

        expect_in_fork do
          expect(component.enabled?).to be true
          expect(component.worker.enabled?).to be true
          expect(component.worker.running?).to be true

          # Queueing an event will restart the worker in the forked child.
          component.worker.enqueue(Datadog::Core::Telemetry::Event::AppHeartbeat.new)

          expect(component.worker.running?).to be true
        end
      end
    end

    describe 'events generated in forked child' do
      before do
        # Reduce interval between event submissions in worker
        # to make the test run faster.
        expect(component.worker).to receive(:loop_wait_time).at_least(:once).and_return(1)
      end

      # Behavior in the child should be the same regardless of what
      # was sent in the parent, because the child is a new application
      # (process) from the backend's perspective.
      def fork_and_assert
        sent_payloads.clear

        expect_in_fork do
          expect(component.worker).to be_running

          component.worker.enqueue(Datadog::Core::Telemetry::Event::AppHeartbeat.new)

          component.flush
        end

        expect(sent_payloads.length).to eq 3

        payload = sent_payloads[0].fetch(:payload)
        expect(payload).to include(
          'request_type' => 'app-started',
        )
        payload = sent_payloads[1].fetch(:payload)
        # The app-dependencies-loaded assertion is also critical here,
        # since there is no other test coverage for the
        # app-dependencies-loaded event being sent in the forked child.
        expect(payload).to include(
          'request_type' => 'app-dependencies-loaded',
        )
        payload = sent_payloads[2].fetch(:payload)
        expect(payload).to include(
          'request_type' => 'message-batch',
        )
        expect(payload.fetch('payload').first).to include(
          'request_type' => 'app-heartbeat',
        )
      end

      context 'when initial event is AppStarted' do
        let(:initial_event) do
          Datadog::Core::Telemetry::Event::AppStarted.new(components: components)
        end

        it 'produces correct events in the child' do
          component.worker.start(initial_event)
          component.flush

          expect(sent_payloads.length).to eq 2

          payload = sent_payloads[0].fetch(:payload)
          expect(payload).to include(
            'request_type' => 'app-started',
          )
          payload = sent_payloads[1].fetch(:payload)
          expect(payload).to include(
            'request_type' => 'app-dependencies-loaded',
          )

          fork_and_assert
        end
      end

      context 'when initial event is SynthAppClientConfigurationChange' do
        let(:initial_event) do
          Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange.new(components: Datadog.send(:components))
        end

        it 'produces correct events in the child' do
          component.worker.start(initial_event)
          component.flush

          expect(sent_payloads.length).to eq 1

          payload = sent_payloads[0].fetch(:payload)
          expect(payload).to include(
            'request_type' => 'app-client-configuration-change',
          )

          fork_and_assert
        end
      end
    end
  end
end
