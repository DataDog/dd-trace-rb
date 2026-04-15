require 'spec_helper'

require 'datadog/core/telemetry/event/app_started'

RSpec.describe Datadog::Core::Telemetry::Event::AppStarted do
  let(:id) { double('seq_id') }
  subject(:event) { described_class.new(components: Datadog.send(:components)) }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(Datadog.configuration) }

  let(:logger) do
    stub_const('MyLogger', Class.new(::Logger)).new(nil)
  end
  let(:default_configuration) do
    [
      ['agent.host', nil],
      ['DD_ENV', nil],
      ['DD_TRACE_SAMPLE_RATE', nil],
      ['DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED', false],
      ['DD_TRACE_DEBUG', false],
      ['DD_TRACE_STARTUP_LOGS', nil],
      ['DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED', false],
      ['DD_TRACE_PEER_SERVICE_MAPPING', ''],
      ['DD_DYNAMIC_INSTRUMENTATION_ENABLED', false],
      ['logger.level', 1],
      ['profiling.advanced.code_provenance_enabled', true],
      ['DD_PROFILING_ENDPOINT_COLLECTION_ENABLED', true],
      ['DD_PROFILING_ENABLED', false],
      ['DD_RUNTIME_METRICS_ENABLED', false],
      ['DD_TRACE_ANALYTICS_ENABLED', nil],
      ['DD_TRACE_PROPAGATION_STYLE_EXTRACT', 'datadog,tracecontext,baggage'],
      ['DD_TRACE_PROPAGATION_STYLE_INJECT', 'datadog,tracecontext,baggage'],
      ['DD_TRACE_ENABLED', true],
      ['DD_LOGS_INJECTION', true],
      ['DD_TRACE_HTTP_SERVER_ERROR_STATUSES', '500..599'],
      ['DD_TRACE_HTTP_CLIENT_ERROR_STATUSES', '400..499'],
      ['tracing.partial_flush.enabled', false],
      ['tracing.partial_flush.min_spans_threshold', 500],
      ['DD_TRACE_REPORT_HOSTNAME', false],
      ['DD_TRACE_RATE_LIMIT', 100],
      # ['tracing.writer_options.buffer_size', 123], # not reported by default
      # ['tracing.writer_options.flush_interval', 456], # not reported by default
      # ['logger.instance', 'MyLogger'], # not reported by default
      ['DD_APPSEC_ENABLED', false],
      # ['DD_APPSEC_SCA_ENABLED', false], # not reported by default
      ['DD_APM_TRACING_ENABLED', true]
    ].freeze
  end
  let(:expected_install_signature) do
    {install_id: 'id', install_time: 'time', install_type: 'type'}
  end
  let(:expected_products) do
    {
      appsec: {
        enabled: false,
      },
      dynamic_instrumentation: {
        enabled: false,
      },
      profiler: hash_including(enabled: false),
    }
  end
  before do
    allow_any_instance_of(Datadog::Core::Utils::Sequence).to receive(:next).and_return(id)
  end

  describe '.payload' do
    it 'contains expected products' do
      expect(event.payload[:products]).to match(expected_products)
    end

    context 'with install signature configured' do
      before do
        Datadog.configure do |c|
          c.telemetry.install_id = 'id'
          c.telemetry.install_type = 'type'
          c.telemetry.install_time = 'time'
        end
      end

      after do
        Datadog.configuration.reset!
      end

      it 'contains expected install signature' do
        expect(event.payload[:install_signature]).to eq(expected_install_signature)
      end
    end

    context 'with git/SCI environment variables set' do
      with_env 'DD_GIT_REPOSITORY_URL' => 'https://github.com/datadog/hello',
        'DD_GIT_COMMIT_SHA' => '1234hash'

      it 'reports git/SCI values to telemetry' do
        expect(event.payload[:configuration]).to include(
          {
            name: 'DD_GIT_REPOSITORY_URL',
            origin: 'env_var',
            seq_id: 3,
            value: 'https://github.com/datadog/hello'
          },
          {name: 'DD_GIT_COMMIT_SHA', origin: 'env_var', seq_id: 3, value: '1234hash'},
        )
      end
    end

    context 'with values set by the customer application' do
      before do
        stub_const('Datadog::AutoInstrument::LOADED', true)
        stub_const('Datadog::OpenTelemetry::LOADED', true)
      end

      it 'reports values set by the customer application' do
        expect(event.payload[:configuration]).to include(
          {name: 'tracing.auto_instrument.enabled', origin: 'code', seq_id: 5, value: true},
          {name: 'tracing.opentelemetry.enabled', origin: 'code', seq_id: 5, value: true},
        )
      end
    end

    context 'with DD_AGENT_TRANSPORT complex origin' do
      it 'reports unknown origin' do
        expect(event.payload[:configuration]).to include(
          {name: 'DD_AGENT_TRANSPORT', origin: 'unknown', seq_id: 7, value: 'TCP'},
        )
      end
    end

    context 'with OpenTelemetry environment variables' do
      with_env 'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://otel:4317',
        'OTEL_EXPORTER_OTLP_HEADERS' => 'key1=value1,key2=value2',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf',
        'OTEL_EXPORTER_OTLP_TIMEOUT' => '5000',
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_METRICS_EXPORTER' => 'otlp',
        'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' => 'http://metrics:4318',
        'OTEL_EXPORTER_OTLP_METRICS_HEADERS' => 'metrics_key=metrics_value',
        'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'http/protobuf',
        'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '3000',
        'OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' => 'cumulative',
        'OTEL_METRIC_EXPORT_INTERVAL' => '4000',
        'OTEL_METRIC_EXPORT_TIMEOUT' => '2000'

      it 'reports OpenTelemetry configurations with environment variable names' do
        expect(event.payload[:configuration]).to include(
          # Environment variables values
          {name: 'OTEL_EXPORTER_OTLP_ENDPOINT', origin: 'env_var', seq_id: 3, value: 'http://otel:4317'},
          {name: 'OTEL_EXPORTER_OTLP_HEADERS', origin: 'env_var', seq_id: 3, value: 'key1=value1,key2=value2'},
          {name: 'OTEL_EXPORTER_OTLP_PROTOCOL', origin: 'env_var', seq_id: 3, value: 'http/protobuf'},
          {name: 'OTEL_EXPORTER_OTLP_TIMEOUT', origin: 'env_var', seq_id: 3, value: 5000},
          {name: 'DD_METRICS_OTEL_ENABLED', origin: 'env_var', seq_id: 3, value: true},
          {name: 'OTEL_METRICS_EXPORTER', origin: 'env_var', seq_id: 3, value: 'otlp'},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT', origin: 'env_var', seq_id: 3, value: 'http://metrics:4318'},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_HEADERS', origin: 'env_var', seq_id: 3, value: 'metrics_key=metrics_value'},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL', origin: 'env_var', seq_id: 3, value: 'http/protobuf'},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT', origin: 'env_var', seq_id: 3, value: 3000},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE', origin: 'env_var', seq_id: 3, value: 'cumulative'},
          {name: 'OTEL_METRIC_EXPORT_INTERVAL', origin: 'env_var', seq_id: 3, value: 4000},
          {name: 'OTEL_METRIC_EXPORT_TIMEOUT', origin: 'env_var', seq_id: 3, value: 2000},
        )
        expect(event.payload[:configuration]).to include(
          # Default values
          {name: 'OTEL_EXPORTER_OTLP_ENDPOINT', origin: 'default', seq_id: 1, value: nil},
          {name: 'OTEL_EXPORTER_OTLP_HEADERS', origin: 'default', seq_id: 1, value: ''},
          {name: 'OTEL_EXPORTER_OTLP_PROTOCOL', origin: 'default', seq_id: 1, value: 'http/protobuf'},
          {name: 'OTEL_EXPORTER_OTLP_TIMEOUT', origin: 'default', seq_id: 1, value: 10000},
          {name: 'DD_METRICS_OTEL_ENABLED', origin: 'default', seq_id: 1, value: false},
          {name: 'OTEL_METRICS_EXPORTER', origin: 'default', seq_id: 1, value: 'otlp'},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT', origin: 'default', seq_id: 1, value: nil},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_HEADERS', origin: 'default', seq_id: 1, value: nil},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL', origin: 'default', seq_id: 1, value: 'http/protobuf'},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT', origin: 'default', seq_id: 1, value: 10000},
          {name: 'OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE', origin: 'default', seq_id: 1, value: 'delta'},
          {name: 'OTEL_METRIC_EXPORT_INTERVAL', origin: 'default', seq_id: 1, value: 10000},
          {name: 'OTEL_METRIC_EXPORT_TIMEOUT', origin: 'default', seq_id: 1, value: 7500}
        )
        expect(event.payload[:configuration].count { |entry| entry[:name] == 'OTEL_EXPORTER_OTLP_HEADERS' && entry[:origin] == 'env_var' }).to eq(1)
        expect(event.payload[:configuration].count { |entry| entry[:name] == 'OTEL_EXPORTER_OTLP_HEADERS' && entry[:origin] == 'default' }).to eq(1)
      end
    end

    context 'with default configuration' do
      it 'reports default configuration' do
        expect(event.payload[:configuration]).to include(*default_configuration.map { |name, value| {name: name, origin: 'default', seq_id: 1, value: value} })
        expect(event.payload[:configuration]).to_not include(*default_configuration.map { |name, value| {name: name, origin: /^((?!default).)*$/, seq_id: anything, value: anything} })
      end
    end

    context 'with set configuration' do
      before do
        Datadog.configure do |c|
          c.agent.host = '1.2.3.4'
          c.env = 'telemetry-env'
          c.tracing.sampling.default_rate = 0.5
          c.tracing.contrib.global_default_service_name.enabled = true
          c.tracing.contrib.peer_service_mapping = {foo: 'bar'}
          c.tracing.writer_options = {buffer_size: 123, flush_interval: 456}
          c.logger.instance = logger
          c.tracing.analytics.enabled = true
          c.appsec.sca_enabled = false
        end
      end

      after do
        Datadog.configuration.reset!
      end

      it 'reports set configuration' do
        expect(event.payload[:configuration]).to include(
          {name: 'agent.host', origin: 'code', seq_id: 5, value: '1.2.3.4'},
          {name: 'DD_ENV', origin: 'code', seq_id: 5, value: 'telemetry-env'},
          {name: 'DD_TRACE_SAMPLE_RATE', origin: 'code', seq_id: 5, value: '0.5'},
          {name: 'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED', origin: 'code', seq_id: 5, value: true},
          {name: 'DD_TRACE_PEER_SERVICE_MAPPING', origin: 'code', seq_id: 5, value: 'foo:bar'},
          {name: 'DD_TRACE_ANALYTICS_ENABLED', origin: 'code', seq_id: 5, value: true},
          {name: 'tracing.writer_options.buffer_size', origin: 'code', seq_id: 5, value: 123},
          {name: 'tracing.writer_options.flush_interval', origin: 'code', seq_id: 5, value: 456},
          {name: 'logger.instance', origin: 'default', seq_id: 1, value: nil},
          {name: 'logger.instance', origin: 'code', seq_id: 5, value: 'MyLogger'},
          {name: 'logger.level', origin: 'code', seq_id: 5, value: 0},
          {name: 'DD_APPSEC_SCA_ENABLED', origin: 'code', seq_id: 5, value: false},
          {name: 'instrumentation_source', origin: 'default', seq_id: 1, value: 'manual'},
          {name: 'DD_INJECT_FORCE', origin: 'default', seq_id: 1, value: false},
          {name: 'DD_INJECTION_ENABLED', origin: 'default', seq_id: 1, value: ''},
        )
        expect(event.payload[:configuration]).to_not include(include(name: 'tracing.writer_options'))
        expect(event.payload[:configuration].count { |entry| entry[:name] == 'logger.instance' && entry[:origin] == 'default' }).to eq(1)
        expect(event.payload[:configuration].count { |entry| entry[:name] == 'logger.instance' && entry[:origin] == 'code' }).to eq(1)
      end
    end

    context 'with stable config' do
      context 'with config id' do
        before do
          allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return(
            {
              fleet: {id: '12345', config: {'DD_APPSEC_ENABLED' => 'true'}},
              local: {id: '56789', config: {'DD_LOGS_INJECTION' => 'false'}},
            }
          )
        end

        it 'reports config id' do
          expect(event.payload[:configuration]).to include(
            {name: 'DD_APPSEC_ENABLED', origin: 'fleet_stable_config', seq_id: 4, value: true, config_id: '12345'},
            {name: 'DD_LOGS_INJECTION', origin: 'local_stable_config', seq_id: 2, value: false, config_id: '56789'},
          )
        end

        context 'without config id' do
          before do
            allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return(
              {
                fleet: {config: {'DD_APPSEC_ENABLED' => 'true'}},
                local: {config: {'DD_LOGS_INJECTION' => 'false'}}
              }
            )
          end

          it 'does not report config id' do
            expect(event.payload[:configuration]).to include(
              {name: 'DD_APPSEC_ENABLED', origin: 'fleet_stable_config', seq_id: 4, value: true},
              {name: 'DD_LOGS_INJECTION', origin: 'local_stable_config', seq_id: 2, value: false},
            )
          end
        end
      end
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
            {name: 'logger.instance', origin: anything, seq_id: anything, value: anything}
          )
        )
      end
    end
  end
end
