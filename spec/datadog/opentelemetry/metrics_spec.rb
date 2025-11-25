# frozen_string_literal: true

require 'spec_helper'

# OpenTelemetry metrics SDK requires Ruby >= 3.1
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1')
  require 'opentelemetry/sdk'
  require 'opentelemetry-metrics-sdk'
  require 'opentelemetry/exporter/otlp_metrics'
end

require 'datadog/opentelemetry'
require 'datadog/core/configuration/settings'
require 'net/http'
require 'json'

RSpec.describe 'OpenTelemetry Metrics Integration', ruby: '>= 3.1' do
  let(:default_otlp_http_port) { 4318 }

  before do
    clear_testagent_metrics
    Datadog.send(:reset!)
    provider = ::OpenTelemetry.meter_provider
    provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
    ::OpenTelemetry.meter_provider = ::OpenTelemetry::Internal::ProxyMeterProvider.new
    allow(Datadog.logger).to receive(:warn)
    allow(Datadog.logger).to receive(:error)
    allow(Datadog.logger).to receive(:debug)
  end

  after do
    provider = ::OpenTelemetry.meter_provider
    # Ensures background threads collecting metrics are shutdown.
    provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
  end

  def agent_host
    Datadog.send(:components).agent_settings.hostname
  end

  def agent_port
    Datadog.send(:components).agent_settings.port
  end

  def clear_testagent_metrics
    uri = URI("http://#{agent_host}:#{default_otlp_http_port}/test/session/clear")
    Net::HTTP.post_form(uri, {})
  rescue => e
    raise "Error clearing testagent metrics: #{e.class}: #{e}"
  end

  def get_testagent_metrics
    uri = URI("http://#{agent_host}:#{default_otlp_http_port}/test/session/metrics")

    try_wait_until(seconds: 2) do
      response = Net::HTTP.get_response(uri)
      next unless response.code == '200'

      parsed = JSON.parse(response.body, symbolize_names: false)
      next parsed if parsed.is_a?(Array) && !parsed.empty?
    end
  end

  def find_metric_in_json(payloads, name)
    payloads.each do |payload|
      payload['resource_metrics']&.each do |rm|
        rm['scope_metrics']&.each do |sm|
          sm['metrics']&.each do |metric|
            return metric if metric['name'] == name
          end
        end
      end
    end
    nil
  end

  def find_attribute_by_key(attributes, key)
    attr = attributes&.find { |a| a['key'] == key }
    attr&.dig('value', 'string_value') || attr&.dig('value', 'int_value') || attr&.dig('value', 'double_value')
  end

  def setup_metrics(env_overrides = {}, &config_block)
    ClimateControl.modify({
      'DD_METRICS_OTEL_ENABLED' => 'true',
      'DD_AGENT_HOST' => agent_host,
    }.merge(env_overrides)) do
      # Reset Datadog to ensure components are reinitialized with the new environment variables
      Datadog.send(:reset!)
      # Set programmatic configurations from tests
      Datadog.configure do |c|
        config_block&.call(c)
      end
      # Enable OpenTelemetry SDK support (which will use the Datadog metrics hook if enabled)
      OpenTelemetry::SDK.configure
    end
  end

  def flush_and_wait(provider)
    return unless provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)

    reader = provider.metric_readers.first
    reader.force_flush if reader&.respond_to?(:force_flush)
    provider.force_flush
  end

  describe 'Basic Functionality' do
    it 'exports counter metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_counter('requests_myapp').add(5)
      flush_and_wait(provider)

      metric = find_metric_in_json(get_testagent_metrics, 'requests_myapp')
      expect(metric['sum']['data_points'].first['as_int'].to_i).to eq(5)
    end

    it 'exports histogram metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_histogram('duration').record(100)
      flush_and_wait(provider)

      metric = find_metric_in_json(get_testagent_metrics, 'duration')
      expect(metric['histogram']['data_points'].first['sum']).to eq(100.0)
    end

    it 'exports gauge metrics' do
      setup_metrics('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' => 'cumulative')
      provider = ::OpenTelemetry.meter_provider
      gauge = provider.meter('app').create_gauge('temperature')

      gauge.record(72)
      gauge.record(72)
      flush_and_wait(provider)

      metrics = get_testagent_metrics
      metric = find_metric_in_json(metrics, 'temperature')
      expect(metric['gauge']['data_points'].length).to eq(1)
      value = metric['gauge']['data_points'].first['as_int']&.to_i
      expect(value).to eq(72)
    end

    it 'exports updowncounter metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_up_down_counter('queue').add(10)
      flush_and_wait(provider)

      metric = find_metric_in_json(get_testagent_metrics, 'queue')
      expect(metric['sum']['data_points'].first['as_int'].to_i).to eq(10)
    end

    it 'handles multiple metric types' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      meter = provider.meter('app')
      meter.create_histogram('size').record(100)
      meter.create_counter('requests.monkey').add(10)
      meter.create_gauge('memory').record(100)
      flush_and_wait(provider)

      metrics = get_testagent_metrics

      size_metric = find_metric_in_json(metrics, 'size')
      expect(size_metric['histogram']['data_points'].first['sum']).to eq(100.0)

      requests_metric = find_metric_in_json(metrics, 'requests.monkey')
      expect(requests_metric['sum']['data_points'].first['as_int'].to_i).to eq(10)

      memory_metric = find_metric_in_json(metrics, 'memory')
      expect(memory_metric['gauge']['data_points'].length).to eq(1)

      gauge_value = memory_metric['gauge']['data_points'].first['as_int']&.to_i
      expect(gauge_value).to eq(100)
    end
  end

  describe 'Resource Attributes' do
    it 'includes service name, version, and environment from Datadog config' do
      setup_metrics(
        'DD_SERVICE' => 'custom-service',
        'DD_VERSION' => '2.0.0',
        'DD_ENV' => 'production',
        'DD_TRACE_REPORT_HOSTNAME' => 'true',
      )

      provider = ::OpenTelemetry.meter_provider
      attributes = provider.instance_variable_get(:@resource).attribute_enumerator.to_h
      expect(attributes['service.name']).to eq('custom-service')
      expect(attributes['service.version']).to eq('2.0.0')
      expect(attributes['deployment.environment']).to eq('production')
      expect(attributes['host.name']).to eq(Datadog::Core::Environment::Socket.hostname)
    end

    it 'includes custom tags as resource attributes' do
      setup_metrics('DD_SERVICE' => 'unused-name', 'DD_VERSION' => 'x.y.z', 'DD_ENV' => 'unused-env', "DD_TAGS" => "host.name:unused-hostname") do |c|
        c.service = 'test-service'
        c.version = '1.0.0'
        c.env = 'test'
        c.tags = {'team' => 'backend', 'region' => 'us-east-1', 'host.name' => 'myhost'}
        c.tracing.report_hostname = true
      end

      provider = ::OpenTelemetry.meter_provider
      attributes = provider.instance_variable_get(:@resource).attribute_enumerator.to_h
      expect(attributes['service.name']).to eq('test-service')
      expect(attributes['service.version']).to eq('1.0.0')
      expect(attributes['deployment.environment']).to eq('test')
      expect(attributes['host.name']).to eq("myhost")
      expect(attributes['team']).to eq('backend')
      expect(attributes['region']).to eq('us-east-1')
    end

    it 'defaults service.name to empty string when neither DD_SERVICE nor service tag is set' do
      # Don't set DD_SERVICE or DD_TAGS with service
      setup_metrics

      provider = ::OpenTelemetry.meter_provider
      attributes = provider.instance_variable_get(:@resource).attribute_enumerator.to_h
      # service_without_fallback returns nil when service equals fallback, so service.name should be empty string
      expect(attributes['service.name']).to eq('')
    end
  end

  describe 'Configuration' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    it 'uses default values when environment variables are not set' do
      setup_metrics

      provider = ::OpenTelemetry.meter_provider
      reader = provider.metric_readers.first
      exporter = reader.instance_variable_get(:@exporter)

      expect(exporter.instance_variable_get(:@uri).to_s).to eq("http://#{agent_host}:4318/v1/metrics")
      expect(exporter.instance_variable_get(:@timeout)).to eq(10.0)
      expect(reader.instance_variable_get(:@export_interval)).to eq(10.0)
      expect(reader.instance_variable_get(:@export_timeout)).to eq(7.5)
    end

    it 'metrics-specific configs take precedence over general OTLP configs' do
      setup_metrics(
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' => 'http://metrics:4318/v1/metrics',
        'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'http/protobuf',
        'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '5000',
        'OTEL_EXPORTER_OTLP_METRICS_HEADERS' => 'metrics=value',
        'OTEL_METRIC_EXPORT_INTERVAL' => '4000',
        'OTEL_METRIC_EXPORT_TIMEOUT' => '3000',
        'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://general:4317',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'grpc',
        'OTEL_EXPORTER_OTLP_TIMEOUT' => '2000',
        'OTEL_EXPORTER_OTLP_HEADERS' => 'general=value'
      )

      provider = ::OpenTelemetry.meter_provider
      reader = provider.metric_readers.first
      exporter = reader.instance_variable_get(:@exporter)

      expect(exporter.instance_variable_get(:@uri).to_s).to eq('http://metrics:4318/v1/metrics')
      expect(exporter.instance_variable_get(:@timeout)).to eq(5.0)
      expect(reader.instance_variable_get(:@export_interval)).to eq(4.0)
      expect(reader.instance_variable_get(:@export_timeout)).to eq(3.0)
      expect(exporter.instance_variable_get(:@headers)['metrics']).to eq('value')
    end

    it 'general OTLP configs work in isolation' do
      setup_metrics(
        'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://general:4317',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf',
        'OTEL_EXPORTER_OTLP_TIMEOUT' => '8000',
        'OTEL_EXPORTER_OTLP_HEADERS' => 'general=value'
      )
      provider = ::OpenTelemetry.meter_provider
      reader = provider.metric_readers.first
      exporter = reader.instance_variable_get(:@exporter)

      expect(exporter.instance_variable_get(:@uri).to_s).to eq('http://general:4317/v1/metrics')
      expect(exporter.instance_variable_get(:@timeout)).to eq(8.0)
      expect(exporter.instance_variable_get(:@headers)['general']).to eq('value')
    end

    it 'parses multiple headers correctly' do
      setup_metrics(
        'OTEL_EXPORTER_OTLP_HEADERS' => 'api-key=secret123,other-config-value=test-value'
      )
      provider = ::OpenTelemetry.meter_provider
      reader = provider.metric_readers.first
      exporter = reader.instance_variable_get(:@exporter)

      headers = exporter.instance_variable_get(:@headers)
      expect(headers['api-key']).to eq('secret123')
      expect(headers['other-config-value']).to eq('test-value')
    end

    it 'uses OTLP exporter when configured' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      exporter = provider.metric_readers.first.instance_variable_get(:@exporter)
      expect(exporter).to be_a(::OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter)

      provider.meter('app').create_counter('test').add(1)
      flush_and_wait(provider)
      metric = find_metric_in_json(get_testagent_metrics, 'test')
      expect(metric['sum']['data_points'].first['as_int'].to_i).to eq(1)
    end

    it 'defaults to HTTP when protocol is set to grpc' do
      setup_metrics(
        'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'grpc'
      )
      settings = Datadog.configuration.opentelemetry.metrics
      expect(settings.protocol).to eq('http/protobuf')
      provider = ::OpenTelemetry.meter_provider
      reader = provider.metric_readers.first
      exporter = reader.instance_variable_get(:@exporter)

      # Should use HTTP port (4318) and path (/v1/metrics) even though grpc was specified
      expect(exporter.instance_variable_get(:@uri).to_s).to eq("http://#{agent_host}:4318/v1/metrics")
    end

    it 'defaults to delta when temporality preference is invalid' do
      setup_metrics(
        'OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' => 'invalid'
      )
      settings = Datadog.configuration.opentelemetry.metrics
      expect(settings.temporality_preference).to eq('delta')
    end

    it 'does not initialize when DD_METRICS_OTEL_ENABLED is false' do
      setup_metrics('DD_METRICS_OTEL_ENABLED' => 'false', 'DD_SERVICE' => 'dd-service')
      provider = ::OpenTelemetry.meter_provider
      resource = provider.instance_variable_get(:@resource)
      attributes = resource.attribute_enumerator.to_h
      expect(attributes['service.name']).not_to eq('dd-service')
    end
  end

  describe 'Multiple Data Points' do
    it 'supports multiple attributes and data points' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      counter = provider.meter('app').create_counter('api')
      counter.add(10, attributes: {'method' => 'GET'})
      counter.add(5, attributes: {'method' => 'POST'})
      flush_and_wait(provider)

      metric = find_metric_in_json(get_testagent_metrics, 'api')
      data_points = metric['sum']['data_points']

      get_point = data_points.find { |dp| find_attribute_by_key(dp['attributes'], 'method') == 'GET' }
      post_point = data_points.find { |dp| find_attribute_by_key(dp['attributes'], 'method') == 'POST' }
      expect(get_point['as_int'].to_i).to eq(10)
      expect(post_point['as_int'].to_i).to eq(5)
    end
  end

  describe 'Lifecycle' do
    it 'handles shutdown gracefully' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      expect { provider.shutdown }.not_to raise_error
      expect { provider.shutdown }.not_to raise_error
    end

    it 'handles force_flush' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_counter('test').add(1)
      expect { provider.force_flush }.not_to raise_error
    end
  end
end
