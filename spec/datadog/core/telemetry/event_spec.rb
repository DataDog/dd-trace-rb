require 'spec_helper'

require 'datadog/core/telemetry/event'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event do
  let(:id) { double('seq_id') }
  let(:event) { event_class.new }

  subject(:payload) { event.payload }

  shared_examples 'event with no attributes' do
    it 'all event instances to the same' do
      event1 = event_class.new
      event2 = event_class.new
      expect(event1).to eq(event2)
      expect(event1.hash).to eq(event2.hash)
    end
  end

  context 'AppStarted' do
    let(:logger) do
      stub_const('MyLogger', Class.new(::Logger)).new(nil)
    end
    let(:event_class) { described_class::AppStarted }
    before do
      allow_any_instance_of(Datadog::Core::Utils::Sequence).to receive(:next).and_return(id)

      Datadog.configure do |c|
        c.agent.host = '1.2.3.4'
        c.tracing.sampling.default_rate = 0.5
        c.tracing.contrib.global_default_service_name.enabled = true
        c.tracing.contrib.peer_service_mapping = { foo: 'bar' }
        c.tracing.writer_options = { buffer_size: 123, flush_interval: 456 }
        c.logger.instance = logger
        c.tracing.analytics.enabled = true
        c.telemetry.install_id = 'id'
        c.telemetry.install_type = 'type'
        c.telemetry.install_time = 'time'
        c.appsec.sca_enabled = false
      end
    end
    it_behaves_like 'event with no attributes'

    it do
      # Helper to make configuration matching table easier to read
      def contain_configuration(*array)
        array.map { |name, value| { name: name, origin: 'code', seq_id: id, value: value } }
      end

      is_expected.to match(
        products: {
          appsec: {
            enabled: false,
          },
          profiler: hash_including(enabled: false),
        },
        configuration: contain_configuration(
          ['DD_AGENT_HOST', '1.2.3.4'],
          ['DD_AGENT_TRANSPORT', 'TCP'],
          ['DD_TRACE_SAMPLE_RATE', '0.5'],
          ['DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED', true],
          ['DD_TRACE_PEER_SERVICE_MAPPING', 'foo:bar'],
          ['logger.level', 0],
          ['profiling.advanced.code_provenance_enabled', true],
          ['profiling.advanced.endpoint.collection.enabled', true],
          ['profiling.enabled', false],
          ['runtime_metrics.enabled', false],
          ['tracing.analytics.enabled', true],
          ['tracing.propagation_style_extract', '["datadog", "tracecontext"]'],
          ['tracing.propagation_style_inject', '["datadog", "tracecontext"]'],
          ['tracing.enabled', true],
          ['tracing.log_injection', true],
          ['tracing.partial_flush.enabled', false],
          ['tracing.partial_flush.min_spans_threshold', 500],
          ['tracing.report_hostname', false],
          ['tracing.sampling.rate_limit', 100],
          ['tracing.auto_instrument.enabled', false],
          ['tracing.writer_options.buffer_size', 123],
          ['tracing.writer_options.flush_interval', 456],
          ['tracing.opentelemetry.enabled', false],
          ['logger.instance', 'MyLogger'],
          ['appsec.enabled', false],
          ['appsec.sca_enabled', false]
        ),
        install_signature: { install_id: 'id', install_time: 'time', install_type: 'type' },
      )
    end

    context 'with nil configurations' do
      before do
        Datadog.configure do |c|
          c.logger.instance = nil
        end
      end

      it 'removes empty configurations from payload' do
        is_expected.to_not match(
          configuration: include(
            { name: 'logger.instance', origin: anything, seq_id: anything, value: anything }
          )
        )
      end
    end
  end

  context 'AppDependenciesLoaded' do
    let(:event_class) { described_class::AppDependenciesLoaded }
    it_behaves_like 'event with no attributes'

    it 'all have name and Ruby gem version' do
      is_expected.to match(dependencies: all(match(name: kind_of(String), version: kind_of(String))))
    end

    it 'has a known gem with expected version' do
      is_expected.to match(
        dependencies: include(name: 'datadog', version: Datadog::Core::Environment::Identity.gem_datadog_version)
      )
    end
  end

  context 'AppIntegrationsChange' do
    let(:event_class) { described_class::AppIntegrationsChange }
    it_behaves_like 'event with no attributes'

    it 'all have name and compatibility' do
      is_expected.to match(integrations: all(include(name: kind_of(String), compatible: boolean)))
    end

    context 'with an instrumented integration' do
      context 'that applied' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :http
          end
        end
        it 'has a list of integrations' do
          is_expected.to match(
            integrations: include(
              name: 'http',
              version: RUBY_VERSION,
              compatible: true,
              enabled: true
            )
          )
        end
      end

      context 'that failed to apply' do
        before do
          raise 'pg is loaded! This test requires integration that does not have its gem loaded' if Gem.loaded_specs['pg']

          Datadog.configure do |c|
            c.tracing.instrument :pg
          end
        end

        it 'has a list of integrations' do
          is_expected.to match(
            integrations: include(
              name: 'pg',
              compatible: false,
              enabled: false,
              error: 'Available?: false, Loaded? false, Compatible? false, Patchable? false',
            )
          )
        end
      end
    end
  end

  context 'AppClientConfigurationChange' do
    let(:event_class) { described_class::AppClientConfigurationChange }
    let(:event) { event_class.new(changes, origin) }
    let(:changes) { { name => value } }
    let(:origin) { double('origin') }
    let(:name) { 'key' }
    let(:value) { 'value' }

    before do
      allow_any_instance_of(Datadog::Core::Utils::Sequence).to receive(:next).and_return(id)
    end

    it 'has a list of client configurations' do
      is_expected.to eq(
        configuration: [{
          name: name,
          value: value,
          origin: origin,
          seq_id: id
        }]
      )
    end

    context 'with env_var state configuration' do
      before do
        Datadog.configure do |c|
          c.appsec.sca_enabled = false
        end
      end

      it 'includes sca enablement configuration' do
        is_expected.to eq(
          configuration:
          [
            { name: name, value: value, origin: origin, seq_id: id },
            { name: 'appsec.sca_enabled', value: false, origin: 'code', seq_id: id }
          ]
        )
      end
    end

    it 'all events to be the same' do
      events =     [
        event_class.new({ 'key' => 'value' }, 'origin'),
        event_class.new({ 'key' => 'value' }, 'origin'),
      ]

      expect(events.uniq).to have(1).item
    end

    it 'all events to be different' do
      events =     [
        event_class.new({ 'key' => 'value' }, 'origin'),
        event_class.new({ 'key' => 'value' }, 'origin2'),
        event_class.new({ 'key' => 'value2' }, 'origin'),
        event_class.new({ 'key2' => 'value' }, 'origin'),
        event_class.new({}, 'origin'),
      ]

      expect(events.uniq).to eq(events)
    end
  end

  context 'AppHeartbeat' do
    let(:event_class) { described_class::AppHeartbeat }
    it_behaves_like 'event with no attributes'

    it 'has no payload' do
      is_expected.to eq({})
    end
  end

  context 'AppClosing' do
    let(:event_class) { described_class::AppClosing }
    it_behaves_like 'event with no attributes'

    it 'has no payload' do
      is_expected.to eq({})
    end
  end

  context 'Logs' do
    let(:event_class) { described_class::Log }

    it do
      event = Datadog::Core::Telemetry::Event::Log.new(message: 'Hi', level: :error)
      expect(event.type).to eq('logs')
      expect(event.payload).to eq(
        {
          logs: [{
            message: 'Hi',
            level: 'ERROR',
            count: 1
          }]
        }
      )
    end

    it do
      event = Datadog::Core::Telemetry::Event::Log.new(message: 'Hi', level: :warn)
      expect(event.type).to eq('logs')
      expect(event.payload).to eq(
        {
          logs: [{
            message: 'Hi',
            level: 'WARN',
            count: 1
          }]
        }
      )
    end

    it do
      expect do
        Datadog::Core::Telemetry::Event::Log.new(message: 'Hi', level: :unknown)
      end.to raise_error(ArgumentError, /Invalid log level/)
    end

    it 'all events to be the same' do
      events =     [
        event_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 1),
        event_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 1),
      ]

      expect(events.uniq).to have(1).item
    end

    it 'all events to be different' do
      events =     [
        event_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 1),
        event_class.new(message: 'Yo', level: :warn, stack_trace: 'stack trace', count: 1),
        event_class.new(message: 'Hi', level: :error, stack_trace: 'stack trace', count: 1),
        event_class.new(message: 'Hi', level: :warn, stack_trace: 'stack&trace', count: 1),
        event_class.new(message: 'Hi', level: :warn, stack_trace: 'stack trace', count: 2),
      ]

      expect(events.uniq).to eq(events)
    end
  end

  context 'GenerateMetrics' do
    let(:event_class) { described_class::GenerateMetrics }
    let(:event) { event_class.new(namespace, metrics) }

    let(:namespace) { 'general' }
    let(:metric_name) { 'request_count' }
    let(:metric) do
      Datadog::Core::Telemetry::Metric::Count.new(metric_name, tags: { status: '200' })
    end
    let(:metrics) { [metric] }

    let(:expected_metric_series) { [metric.to_h] }

    it do
      is_expected.to eq(
        {
          namespace: namespace,
          series: expected_metric_series
        }
      )
    end

    it 'all events to be the same' do
      events =     [
        event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
        event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
      ]

      expect(events.uniq).to have(1).item
    end

    it 'all events to be different' do
      events =     [
        event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
        event_class.new('nospace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
        event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '2' })]),
        event_class.new('namespace', []),

      ]

      expect(events.uniq).to eq(events)
    end
  end

  context 'Distributions' do
    let(:event_class) { described_class::Distributions }
    let(:event) { event_class.new(namespace, metrics) }

    let(:namespace) { 'general' }
    let(:metric_name) { 'request_duration' }
    let(:metric) do
      Datadog::Core::Telemetry::Metric::Distribution.new(metric_name, tags: { status: '200' })
    end
    let(:metrics) { [metric] }

    let(:expected_metric_series) { [metric.to_h] }

    it do
      is_expected.to eq(
        {
          namespace: namespace,
          series: expected_metric_series
        }
      )
    end
  end

  context 'MessageBatch' do
    let(:event_class) { described_class::MessageBatch }
    let(:event) { event_class.new(events) }

    let(:events) { [described_class::AppClosing.new, described_class::AppHeartbeat.new] }

    it do
      is_expected.to eq(
        [
          {
            request_type: 'app-closing',
            payload: {}
          },
          {
            request_type: 'app-heartbeat',
            payload: {}
          }
        ]
      )
    end
  end
end
