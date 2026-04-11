# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/component'

RSpec.describe 'Telemetry integration tests' do
  skip_unless_integration_testing_enabled

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
        'process_tags' => String,
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
        'kernel_version' => ((RUBY_ENGINE == 'jruby') ? nil : String),
      }
    end

    let(:expected_products_hash) do
      {
        'appsec' => {'enabled' => false},
        'dynamic_instrumentation' => {'enabled' => false},
        'profiler' => {'enabled' => false},
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
        expect(Datadog::Profiling).to receive(:unsupported_reason).at_least(:once).and_return(nil)
      end
    end

    describe 'initial event' do
      before do
        settings.telemetry.dependency_collection = true
      end

      context 'when not asked to send configuration change event' do
        include_context 'disable profiling'

        it 'sends app-started' do
          component.start(false, components: Datadog.send(:components))

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
          component.start(true, components: Datadog.send(:components))

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
          component.start(false, components: Datadog.send(:components))

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
        component.start(false, components: Datadog.send(:components))
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
        component.start(false, components: Datadog.send(:components))
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
        component.start(false, components: Datadog.send(:components))
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

    describe 'process tags' do
      include_context 'disable profiling'

      before do
        settings.telemetry.dependency_collection = true
      end

      context 'when process tags propagation is enabled' do
        let(:expected_application_hash) do
          super().merge('process_tags' => String)
        end

        it 'includes process tags in the payload when the process tags have values' do
          allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(true)

          component.start(false, components: Datadog.send(:components))
          component.flush
          expect(sent_payloads.length).to eq 2

          payload = sent_payloads[0]
          expect(payload.fetch(:payload)).to match(
            'api_version' => 'v2',
            'application' => expected_application_hash,
            'debug' => false,
            'host' => expected_host_hash,
            'payload' => Hash,
            'request_type' => 'app-started',
            'runtime_id' => String,
            'seq_id' => Integer,
            'tracer_time' => Integer,
          )

          expect(payload.dig(:payload, 'application', 'process_tags')).to include('entrypoint.workdir')
          expect(payload.dig(:payload, 'application', 'process_tags')).to include('entrypoint.basedir')
          expect(payload.dig(:payload, 'application', 'process_tags')).to include('entrypoint.type')
          expect(payload.dig(:payload, 'application', 'process_tags')).to include('entrypoint.name')
        end
      end

      context 'when process tags propagation is disabled' do
        it 'does not include process_tags in the payload' do
          allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(false)

          component.start(false, components: Datadog.send(:components))
          component.flush
          expect(sent_payloads.length).to eq 2

          payload = sent_payloads[0]
          expect(payload.dig(:payload, 'application')).not_to have_key('process_tags')
        end
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

      component.start(false, components: Datadog.send(:components))

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

      component.start(false, components: Datadog.send(:components))

      component.worker.flush

      # Network I/O is mocked
    end
  end

  describe 'app-started event payloads when components are enabled' do
    # The test cases here are more like unit tests in that they really want
    # to assert the contents of generated events.
    # However, the event creation logic is rather cumbersome, and there is
    # no single point to spy on. AppStarted constructor is perhaps the best
    # candidate, but this would assert on what is created rather than what is
    # actually sent over the wire, which still wouldn't be a straightforward
    # mapping from what we want to test (which are actual payloads).
    # Therefore, these tests go through a local web server and assert on the
    # submitted payloads.
    #
    # These tests are also subject to a race of sorts between when the
    # telemetry worker performs its first iteration and when the
    # app integrations change event is submitted to the queue.
    # Since the tests flush the queue, if the integration change event is
    # submitted after the initial worker iteration, each test will wait for
    # 10 seconds for the second iteration to send out that event.
    # To work around this we reduce metrics_aggregation_interval_seconds to
    # 1 (second).
    # Note that this is (sort of) not an issue in production: all of the
    # events will be sent, but telemetry does not guarantee when any particular
    # event will be sent - it could be delayed until the next worker iteration.

    http_server do |http_server|
      http_server.mount_proc('/telemetry/proxy/api/v2/apmtelemetry', &handler_proc)
    end

    after do
      Datadog.configuration.reset!
    end

    let(:settings) do
      Datadog.configuration
    end

    let(:component) { Datadog.send(:components).telemetry }

    # Override in inner contexts to set up mocks before Datadog.configure runs.
    let(:product_mock_setup) { nil }

    # Override in inner contexts to set product-specific settings.
    let(:product_configuration) { ->(c) {} }

    before do
      product_mock_setup

      Datadog.configure do |c|
        c.agent.port = http_server_port
        c.telemetry.enabled = true
        c.telemetry.metrics_aggregation_interval_seconds = 1

        product_configuration.call(c)
      end
    end

    def assert_remaining_events
      # For sanity checking verify that the remaining events are as we
      # expect them to be. Search by content rather than index — some test
      # cases emit extra telemetry events (error logs, WAF metrics) that
      # shift the payload order depending on Ruby version and environment.
      deps_payload = sent_payloads.find { |p| p.fetch(:payload)['request_type'] == 'app-dependencies-loaded' }
      expect(deps_payload).not_to be_nil

      integrations_batch = sent_payloads.find do |p|
        p.fetch(:payload)['request_type'] == 'message-batch' &&
          Array(p.fetch(:payload)['payload']).any? { |e| e['request_type'] == 'app-integrations-change' }
      end
      expect(integrations_batch).not_to be_nil
    end

    # Configuration names use env var names (DD_PROFILING_ENABLED, not
    # profiling.enabled) because AppStarted#option_telemetry_name prefers
    # option.definition.env over the setting path when an env var is defined.
    shared_examples 'reports requested configuration and actual product state' do |product_key:, configuration:, actual_state:|
      requested = configuration[:value]
      running = actual_state.fetch('enabled')

      it "reports #{product_key} as configured #{requested} and actually #{running ? 'enabled' : 'disabled'}" do
        component.flush
        # There may be more than 3 payloads when component initialization emits
        # telemetry error events (e.g. AppSec logging why it failed to start).
        expect(sent_payloads.length).to be >= 3

        # Find app-started by content rather than index — extra telemetry events
        # may arrive before or after, depending on Ruby version and timing.
        app_started = sent_payloads.find { |p| p.fetch(:payload)['request_type'] == 'app-started' }
        expect(app_started).not_to be_nil
        payload = app_started.fetch(:payload)

        expect(payload.dig('payload', 'configuration')).to include(
          {'name' => configuration[:name], 'value' => configuration[:value], 'origin' => 'code', 'seq_id' => Integer},
        )
        expect(payload.dig('payload', 'products')).to include(
          product_key => actual_state,
        )

        assert_remaining_events
      end
    end

    context 'when profiling is disabled' do
      let(:product_mock_setup) do
        # Avoid profiling reporting unsupported errors when disabled
        expect(Datadog::Profiling).to receive(:unsupported_reason).at_least(:once).and_return(nil)
      end

      let(:product_configuration) { ->(c) { c.profiling.enabled = false } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'profiler',
        configuration: {name: 'DD_PROFILING_ENABLED', value: false},
        actual_state: {'enabled' => false}
    end

    context 'when profiling is fully enabled' do
      let(:product_mock_setup) do
        # Mock profiling as supported
        expect(Datadog::Profiling).to receive(:unsupported_reason).at_least(:once).and_return(nil)

        # Profiling tests require building the native extension (via `bundle exec rake compile`)
        # or mocking the entire profiler object. We mock it here to allow tests to run in
        # environments where the native extension hasn't been compiled.
        fake_profiler = Object.new
        def fake_profiler.shutdown!
        end

        def fake_profiler.start
        end

        allow(Datadog::Profiling::Component).to receive(:build_profiler_component).and_return([fake_profiler, nil])
      end

      let(:product_configuration) { ->(c) { c.profiling.enabled = true } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'profiler',
        configuration: {name: 'DD_PROFILING_ENABLED', value: true},
        actual_state: {'enabled' => true}
    end

    context 'when profiling is requested to be enabled but fails prerequisites' do
      let(:product_mock_setup) do
        expect(Datadog::Profiling).to receive(:unsupported_reason).at_least(:once).and_return('fake not supported reason')
      end

      let(:product_configuration) { ->(c) { c.profiling.enabled = true } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'profiler',
        configuration: {name: 'DD_PROFILING_ENABLED', value: true},
        actual_state: {
          'enabled' => false,
          'error' => {
            'code' => 1,
            'message' => 'fake not supported reason',
          },
        }
    end

    context 'when dynamic instrumentation is disabled' do
      let(:product_configuration) { ->(c) { c.dynamic_instrumentation.enabled = false } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'dynamic_instrumentation',
        configuration: {name: 'DD_DYNAMIC_INSTRUMENTATION_ENABLED', value: false},
        actual_state: {'enabled' => false}
    end

    context 'when dynamic instrumentation is fully enabled' do
      let(:product_mock_setup) do
        # DI requires a C extension and MRI Ruby 2.6+, which are not
        # available in all CI configurations. Mock the component build
        # so the test can run everywhere, same approach as profiling.
        fake_di = Object.new
        def fake_di.shutdown!
        end

        allow(Datadog::DI::Component).to receive(:build).and_return(fake_di)
      end

      let(:product_configuration) do
        lambda { |c|
          c.dynamic_instrumentation.enabled = true
          c.dynamic_instrumentation.internal.development = true
          c.remote.enabled = true
        }
      end

      include_examples 'reports requested configuration and actual product state',
        product_key: 'dynamic_instrumentation',
        configuration: {name: 'DD_DYNAMIC_INSTRUMENTATION_ENABLED', value: true},
        actual_state: {'enabled' => true}
    end

    context 'when dynamic instrumentation is requested to be enabled but fails prerequisites' do
      let(:product_configuration) do
        lambda { |c|
          c.dynamic_instrumentation.enabled = true
          # Disable remote config which is a prerequisite for DI
          c.remote.enabled = false
        }
      end

      include_examples 'reports requested configuration and actual product state',
        product_key: 'dynamic_instrumentation',
        configuration: {name: 'DD_DYNAMIC_INSTRUMENTATION_ENABLED', value: true},
        actual_state: {
          'enabled' => false,
          # DI currently does not provide the reason why it's not enabled.
        }
    end

    context 'when appsec is disabled' do
      let(:product_configuration) { ->(c) { c.appsec.enabled = false } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'appsec',
        configuration: {name: 'DD_APPSEC_ENABLED', value: false},
        actual_state: {'enabled' => false}
    end

    context 'when appsec is fully enabled' do
      let(:product_configuration) { ->(c) { c.appsec.enabled = true } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'appsec',
        configuration: {name: 'DD_APPSEC_ENABLED', value: true},
        actual_state: {'enabled' => true}
    end

    context 'when appsec is requested to be enabled but fails prerequisites' do
      let(:product_mock_setup) do
        # Simulate FFI gem not being loaded (prerequisite check)
        fake_specs = Gem.loaded_specs.dup
        fake_specs.delete('ffi')
        allow(Gem).to receive(:loaded_specs).and_return(fake_specs)
      end

      let(:product_configuration) { ->(c) { c.appsec.enabled = true } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'appsec',
        configuration: {name: 'DD_APPSEC_ENABLED', value: true},
        actual_state: {
          'enabled' => false,
          # AppSec currently does not provide the reason why it's not enabled.
        }
    end

    context 'when appsec is requested to be enabled but fails initialization' do
      let(:product_mock_setup) do
        # AppSec has very modest prerequisites, it's easier to fail
        # its initialization than to make the prerequisites not fulfilled.
        expect(Datadog::AppSec::SecurityEngine::Engine).to receive(:new).and_raise("fake exception")
      end

      let(:product_configuration) { ->(c) { c.appsec.enabled = true } }

      include_examples 'reports requested configuration and actual product state',
        product_key: 'appsec',
        configuration: {name: 'DD_APPSEC_ENABLED', value: true},
        actual_state: {
          'enabled' => false,
          # AppSec currently does not provide the reason why it's not enabled.
        }
    end
  end
end
