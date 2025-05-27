# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/component'

RSpec.describe 'Telemetry integration tests' do
  # Although the tests override the environment variables, if any,
  # with programmatic configuration, that may produce warnings from the
  # configuration code. Remove environment variables to suppress the warnings.
  # DD_AGENT_HOST is set in CI and *must* be overridden.
  with_env DD_TRACE_AGENT_PORT: nil,
    DD_TRACE_AGENT_URL: nil,
    DD_AGENT_HOST: nil

  let(:component) do
    Datadog::Core::Telemetry::Component.build(settings, agent_settings, logger)
  end

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings)
  end

  let(:logger) { logger_allowing_debug }

  after do
    component.shutdown!
  end

  let(:sent_payloads) { [] }

  shared_examples 'telemetry integration tests' do
    it 'initializes correctly' do
      expect(component.enabled).to be true
    end

    let(:expected_base_headers) do
      {
        # Webrick provides each header value as an array
        'dd-client-library-language' => %w[ruby],
        'dd-client-library-version' => [String],
        'dd-internal-untraced-request' => %w[1],
        'dd-telemetry-api-version' => %w[v2],
      }
    end

    let(:expected_agentless_headers) do
      expected_base_headers.merge(
        'dd-api-key' => %w[1234],
      )
    end

    let(:expected_application_hash) do
      {
        'env' => nil,
        'language_name' => 'ruby',
        'language_version' => String,
        'runtime_name' => /\Aj?ruby\z/i,
        'runtime_version' => String,
        'service_name' => String,
        'service_version' => nil,
        'tracer_version' => String,
      }
    end

    let(:expected_host_hash) do
      {
        'architecture' => String,
        'hostname' => String,
        'kernel_name' => String,
        'kernel_release' => String,
        'kernel_version' => (RUBY_ENGINE == 'jruby' ? nil : String),
      }
    end

    let(:expected_products_hash) do
      {
        'appsec' => { 'enabled' => false },
        'dynamic_instrumentation' => { 'enabled' => false },
        'profiler' => { 'enabled' => false },
      }
    end

    shared_context 'disable profiling' do
      before do
        # Profiling will return the unsupported reason, and telemetry will
        # report it as an error, even if profiling was not requested to
        # be enabled.
        # The most common unsupported reason is failure to load profiling
        # C extension due to it not having been compiled - we get that in
        # some CI configurations.
        expect(Datadog::Profiling).to receive(:enabled?).and_return(false)
        expect(Datadog::Profiling).to receive(:unsupported_reason).and_return(nil)
      end
    end

    describe 'initial event' do
      before do
        settings.telemetry.dependency_collection = true
      end

      context 'when not asked to send configuration change event' do
        include_context 'disable profiling'

        it 'sends app-started' do
          component.start

          component.flush
          expect(sent_payloads.length).to eq 2

          payload = sent_payloads[0]
          expect(payload.fetch(:payload)).to match(
            'api_version' => 'v2',
            'application' => expected_application_hash,
            'debug' => false,
            'host' => expected_host_hash,
            'payload' => {
              'configuration' => Array,
              'products' => expected_products_hash,
              'install_signature' => Hash,
            },
            'request_type' => 'app-started',
            'runtime_id' => String,
            'seq_id' => Integer,
            'tracer_time' => Integer,
          )
          expect(payload.fetch(:headers)).to include(
            expected_headers.merge('dd-telemetry-request-type' => %w[app-started])
          )
        end
      end

      context 'when asked to send configuration change event' do
        it 'sends app-client-configuration-change' do
          component.start(true)

          component.flush
          expect(sent_payloads.length).to eq 1

          payload = sent_payloads[0]
          expect(payload.fetch(:payload)).to match(
            'api_version' => 'v2',
            'application' => expected_application_hash,
            'debug' => false,
            'host' => expected_host_hash,
            'payload' => {
              'configuration' => Array,
            },
            'request_type' => 'app-client-configuration-change',
            'runtime_id' => String,
            'seq_id' => Integer,
            'tracer_time' => Integer,
          )
          expect(payload.fetch(:headers)).to include(
            expected_headers.merge('dd-telemetry-request-type' => %w[app-client-configuration-change])
          )
        end
      end
    end

    describe 'app-dependencies-loaded event' do
      include_context 'disable profiling'

      context 'when dependency collection is enabled' do
        before do
          settings.telemetry.dependency_collection = true
        end

        it 'sends app-dependencies-loaded event' do
          component.start

          component.flush
          expect(sent_payloads.length).to eq 2

          payload = sent_payloads[0]
          expect(payload.fetch(:payload)).to include(
            'request_type' => 'app-started',
          )

          payload = sent_payloads[1]
          expect(payload.fetch(:payload)).to match(
            'api_version' => 'v2',
            'application' => expected_application_hash,
            'debug' => false,
            'host' => expected_host_hash,
            'payload' => {
              'dependencies' => Array,
            },
            'request_type' => 'app-dependencies-loaded',
            'runtime_id' => String,
            'seq_id' => Integer,
            'tracer_time' => Integer,
          )
          expect(payload.fetch(:headers)).to include(
            expected_headers.merge('dd-telemetry-request-type' => %w[app-dependencies-loaded])
          )
        end
      end
    end

    describe 'error event' do
      before do
        expect(component.worker).to receive(:sent_initial_event?).at_least(:once).and_return(true)
        component.start
      end

      it 'sends expected payload' do
        ok = component.error('test error')
        expect(ok).to be true

        component.flush
        expect(sent_payloads.length).to eq 1

        payload = sent_payloads[0]
        expect(payload.fetch(:payload)).to match(
          'api_version' => 'v2',
          'application' => expected_application_hash,
          'debug' => false,
          'host' => expected_host_hash,
          'payload' => [
            'payload' => {
              'logs' => [
                'count' => 1,
                'level' => 'ERROR',
                'message' => 'test error',
              ],
            },
            'request_type' => 'logs',
          ],
          'request_type' => 'message-batch',
          'runtime_id' => String,
          'seq_id' => Integer,
          'tracer_time' => Integer,
        )
        expect(payload.fetch(:headers)).to include(
          expected_headers.merge('dd-telemetry-request-type' => %w[message-batch])
        )
      end
    end

    describe 'heartbeat event' do
      before do
        expect(component.worker).to receive(:sent_initial_event?).at_least(:once).and_return(true)
        component.start
      end

      it 'sends expected payload' do
        component.worker.send(:heartbeat!)
        component.worker.flush
        expect(sent_payloads.length).to eq 1

        payload = sent_payloads[0]
        expect(payload.fetch(:payload)).to match(
          'api_version' => 'v2',
          'application' => expected_application_hash,
          'debug' => false,
          'host' => expected_host_hash,
          'payload' => {},
          'request_type' => 'app-heartbeat',
          'runtime_id' => String,
          'seq_id' => Integer,
          'tracer_time' => Integer,
        )
        expect(payload.fetch(:headers)).to include(
          expected_headers.merge('dd-telemetry-request-type' => %w[app-heartbeat])
        )
      end
    end

    context 'when telemetry debugging is enabled in settings' do
      before do
        settings.telemetry.debug = true

        expect(component.worker).to receive(:sent_initial_event?).at_least(:once).and_return(true)
        component.start
      end

      it 'sets debug to true in payload' do
        component.worker.send(:heartbeat!)
        component.worker.flush
        expect(sent_payloads.length).to eq 1

        payload = sent_payloads[0]
        expect(payload.fetch(:payload)).to match(
          'api_version' => 'v2',
          'application' => expected_application_hash,
          'debug' => true,
          'host' => expected_host_hash,
          'payload' => {},
          'request_type' => 'app-heartbeat',
          'runtime_id' => String,
          'seq_id' => Integer,
          'tracer_time' => Integer,
        )
        expect(payload.fetch(:headers)).to include(
          expected_headers.merge('dd-telemetry-request-type' => %w[app-heartbeat])
        )
      end
    end
  end

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

  shared_context 'agent mode' do
    http_server do |http_server|
      http_server.mount_proc('/telemetry/proxy/api/v2/apmtelemetry', &handler_proc)
    end

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.agent.port = http_server_port
        settings.telemetry.enabled = true
      end
    end

    let(:expected_headers) { expected_base_headers }
  end

  context 'in agent mode' do
    include_context 'agent mode'

    include_examples 'telemetry integration tests'

    context 'agent listening on UDS' do
      define_http_server_uds do |http_server|
        http_server.mount_proc('/telemetry/proxy/api/v2/apmtelemetry', &handler_proc)
      end

      let(:settings) do
        Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.agent.uds_path = uds_socket_path
          settings.telemetry.enabled = true
        end
      end

      include_examples 'telemetry integration tests'
    end
  end

  context 'in agentless mode' do
    http_server do |http_server|
      http_server.mount_proc('/api/v2/apmtelemetry', &handler_proc)
    end

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.agent.port = http_server_port
        settings.telemetry.enabled = true
        settings.telemetry.agentless_enabled = true
        settings.telemetry.agentless_url_override = "http://127.0.0.1:#{http_server_port}"
        settings.api_key = '1234'
      end
    end

    let(:expected_headers) { expected_agentless_headers }

    include_examples 'telemetry integration tests'
  end

  context 'when events are enqueued prior to start' do
    # The mode is irrelevant for these tests, there is no need to test
    # both modes therefore we choose an arbitrary one here.
    include_context 'agent mode'

    let(:event) do
      Datadog::Core::Telemetry::Event::Log.new(message: 'test log entry', level: :error)
    end

    it 'stores the events and sends them after start' do
      component.log!(event)

      expect(component.worker.buffer.length).to eq 1

      component.start

      component.worker.flush
      expect(sent_payloads.length).to eq 3

      payload = sent_payloads[0]
      expect(payload.fetch(:payload)).to include(
        'request_type' => 'app-started',
      )

      payload = sent_payloads[1]
      expect(payload.fetch(:payload)).to include(
        'request_type' => 'app-dependencies-loaded',
      )

      # The logs are sent after app-started event
      payload = sent_payloads[2]
      expect(payload.fetch(:payload)).to include(
        'request_type' => 'message-batch',
        'payload' => [{
          'payload' => {
            'logs' => [
              'count' => 1,
              'level' => 'ERROR',
              'message' => 'test log entry',
            ],
          },
          'request_type' => 'logs',
        }],
      )
    end
  end

  context 'when initial event fails' do
    let(:settings) do
    ENV['DD_TRACE_DEBUG']=      'true'
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.telemetry.enabled = true
        # Setting heartbeat interval does not appear to make the worker
        # run iterations any faster?
        #settings.telemetry.heartbeat_interval_seconds = 0.1
      end
    end

    let(:failed_response) do
      double(Datadog::Core::Transport::HTTP::Adapters::Net::Response).tap do |response|
        expect(response).to receive(:ok?).and_return(false).at_least(:once)
      end
    end

    let(:ok_response) do
      double(Datadog::Core::Transport::HTTP::Adapters::Net::Response).tap do |response|
        expect(response).to receive(:ok?).and_return(true).at_least(:once)
      end
    end

    let(:event) do
      Datadog::Core::Telemetry::Event::Log.new(message: 'test log entry', level: :error)
    end

    it 'retries the initial event and delays log until after initial event succeeds' do
      component.log!(event)

      expect(component.worker.buffer.length).to eq 1

      allow(component.worker).to receive(:send_event).with(
        an_instance_of(Datadog::Core::Telemetry::Event::AppHeartbeat)
      ).and_return(ok_response)

      expect(component.worker).to receive(:send_event).with(
        an_instance_of(Datadog::Core::Telemetry::Event::AppStarted)
      ).ordered.and_return(failed_response)
      expect(component.worker).to receive(:send_event).with(
        an_instance_of(Datadog::Core::Telemetry::Event::AppStarted)
      ).ordered.and_return(ok_response)
      expect(component.worker).to receive(:send_event).with(
        an_instance_of(Datadog::Core::Telemetry::Event::AppDependenciesLoaded)
      ).ordered.and_return(ok_response)
      expect(component.worker).to receive(:send_event).with(
        an_instance_of(Datadog::Core::Telemetry::Event::MessageBatch)
      ).ordered.and_return(ok_response)

      component.start

      component.worker.flush

      # Network I/O is mocked
    end
  end
end
