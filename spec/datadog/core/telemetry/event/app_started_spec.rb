require 'spec_helper'

require 'datadog/core/telemetry/event/app_started'

RSpec.describe Datadog::Core::Telemetry::Event::AppStarted do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  subject(:payload) { event.payload }

  let(:logger) do
    stub_const('MyLogger', Class.new(::Logger)).new(nil)
  end
  let(:default_code_configuration) do
    [
      ['DD_AGENT_HOST', '1.2.3.4'],
      ['DD_AGENT_TRANSPORT', 'TCP'],
      ['DD_TRACE_SAMPLE_RATE', '0.5'],
      ['DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED', true],
      ['DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED', false],
      ['DD_TRACE_PEER_SERVICE_MAPPING', 'foo:bar'],
      ['dynamic_instrumentation.enabled', false],
      ['logger.level', 0],
      ['profiling.advanced.code_provenance_enabled', true],
      ['profiling.advanced.endpoint.collection.enabled', true],
      ['profiling.enabled', false],
      ['runtime_metrics.enabled', false],
      ['tracing.analytics.enabled', true],
      ['tracing.propagation_style_extract', '["datadog", "tracecontext", "baggage"]'],
      ['tracing.propagation_style_inject', '["datadog", "tracecontext", "baggage"]'],
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
    ].freeze
  end
  let(:expected_install_signature) do
    { install_id: 'id', install_time: 'time', install_type: 'type' }
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

    # Reset global cache
    Datadog::Core::Environment::Git.reset_for_tests
  end
  it_behaves_like 'telemetry event with no attributes'

  # Helper to make configuration matching table easier to read
  def contain_code_configuration(*array)
    array.map { |name, value| { name: name, origin: 'code', seq_id: id, value: value } }
  end

  def contain_env_configuration(*array)
    array.map { |name, value| { name: name, origin: 'env_var', seq_id: id, value: value } }
  end

  it do
    is_expected.to match(
      products: expected_products,
      configuration: contain_code_configuration(
        *default_code_configuration
      ),
      install_signature: expected_install_signature,
    )
  end

  context 'with git/SCI environment variables set' do
    with_env 'DD_GIT_REPOSITORY_URL' => 'https://github.com/datadog/hello',
      'DD_GIT_COMMIT_SHA' => '1234hash'

    before do
      # Reset global cache so that we get our values back
      Datadog::Core::Environment::Git.reset_for_tests
    end

    after do
      # Do not use our values in other tests
      Datadog::Core::Environment::Git.reset_for_tests
    end

    it 'reports git/SCI values to telemetry' do
      is_expected.to match(
        products: expected_products,
        configuration: contain_env_configuration(
          ['DD_GIT_REPOSITORY_URL', 'https://github.com/datadog/hello'],
          ['DD_GIT_COMMIT_SHA', '1234hash'],
        ) + contain_code_configuration(
          *default_code_configuration
        ),
        install_signature: expected_install_signature,
      )
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
          { name: 'logger.instance', origin: anything, seq_id: anything, value: anything }
        )
      )
    end
  end
end
