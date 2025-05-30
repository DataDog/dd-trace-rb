# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/component'

# https://github.com/rubocop/rubocop-rspec/issues/2078
# rubocop:disable RSpec/ScatteredLet

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
    # TODO: why is there no shutdown! method on telemetry component?
    component.stop!
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

    describe 'startup events' do
      before do
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.send(:reset_ran_once_state_for_tests)
      end

      it 'sends expected startup events' do
        expect(settings.telemetry.dependency_collection).to be true

        # Profiling will return the unsupported reason, and telemetry will
        # report it as an error, even if profiling was not requested to
        # be enabled.
        # The most common unsupported reason is failure to load profiling
        # C extension due to it not having been compiled - we get that in
        # some CI configurations.
        expect(Datadog::Profiling).to receive(:enabled?).and_return(false)
        expect(Datadog::Profiling).to receive(:unsupported_reason).and_return(nil)

        # Instantiate the component
        component

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

    describe 'error event' do
      # To avoid noise from the startup events, turn those off.
      mark_telemetry_started

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
      mark_telemetry_started

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
      mark_telemetry_started

      before do
        settings.telemetry.debug = true
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

  context 'in agent mode' do
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
end

# rubocop:enable RSpec/ScatteredLet
