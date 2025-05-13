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

    describe 'startup events' do
      before do
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.send(:reset_ran_once_state_for_tests)
      end

      it 'sends expected startup events' do
        expect(settings.telemetry.dependency_collection).to be true

        # Instantiate the component
        component

        component.flush
        expect(sent_payloads.length).to eq 2

        payload = sent_payloads[0]
        expect(payload.fetch(:payload)).to match(
          'api_version' => 'v2',
          'application' => Hash,
          'debug' => false,
          'host' => Hash,
          'payload' => {
            'configuration' => Array,
            'products' => Hash,
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
          'application' => Hash,
          'debug' => false,
          'host' => Hash,
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
        component.error('test error')

        component.flush
        expect(sent_payloads.length).to eq 1

        payload = sent_payloads[0]
        expect(payload.fetch(:payload)).to match(
          'api_version' => 'v2',
          'application' => Hash,
          'debug' => false,
          'host' => Hash,
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
