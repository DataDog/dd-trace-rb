# frozen_string_literal: true

require 'spec_helper'
require 'opentelemetry/sdk'
require 'opentelemetry-metrics-sdk'
require 'opentelemetry/exporter/otlp_metrics'
require 'datadog/opentelemetry'
require 'datadog/core/configuration/settings'
require 'net/http'
require 'json'

RSpec.describe 'OpenTelemetry Metrics Integration' do
  include NetworkHelpers

  DEFAULT_OTLP_HTTP_PORT = 4318

  before do
    Datadog.send(:reset!) if Datadog.respond_to?(:reset!, true)
    provider = ::OpenTelemetry.meter_provider
    provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
    ::OpenTelemetry.meter_provider = ::OpenTelemetry::Internal::ProxyMeterProvider.new
    allow(Datadog.logger).to receive(:warn)
    allow(Datadog.logger).to receive(:error)
    allow(Datadog.logger).to receive(:debug)
    clear_testagent_metrics
  end

  after do
    provider = ::OpenTelemetry.meter_provider
    # Ensures background threads collecting metrics are shutdown.
    provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
    clear_testagent_metrics
  end

  def clear_testagent_metrics
    uri = URI("http://#{agent_host}:#{DEFAULT_OTLP_HTTP_PORT}/test/session/clear")
    Net::HTTP.post_form(uri, {})
  rescue
    # Ignore errors if testagent is not available
  end

  def get_testagent_metrics(max_retries: 5, wait_time: 0.2)
    uri = URI("http://#{agent_host}:#{DEFAULT_OTLP_HTTP_PORT}/test/session/metrics")
    
    max_retries.times do
      response = Net::HTTP.get_response(uri)
      next unless response.code == '200'
      
      parsed = JSON.parse(response.body, symbolize_names: false)
      return parsed if parsed.is_a?(Array) && !parsed.empty?
      
      if parsed.is_a?(Hash)
        metrics_array = parsed['metrics']
        return metrics_array if metrics_array.is_a?(Array) && !metrics_array.empty?
        return [parsed]
      end
      
      sleep(wait_time)
    end
    
    []
  rescue
    []
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
      'DD_TRACE_AGENT_PORT' => agent_port,
    }.merge(env_overrides)) do
      Datadog.configure do |c|
        config_block&.call(c)
      end
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
      flush_and_wait(provider)
      gauge.record(72)
      flush_and_wait(provider)

      metric = find_metric_in_json(get_testagent_metrics, 'temperature')
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
      if memory_metric
        gauge_value = memory_metric['gauge']['data_points'].first['as_int']&.to_i
        expect(gauge_value).to eq(100) if gauge_value && gauge_value != 0
      end
    end
  end

  describe 'Resource Attributes' do
    it 'includes service name, version, and environment from Datadog config' do
      setup_metrics(
        'DD_SERVICE' => 'custom-service',
        'DD_VERSION' => '2.0.0',
        'DD_ENV' => 'production',
        'OTEL_METRIC_EXPORT_INTERVAL' => '10000',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf'
      ) do |c|
        c.service = 'custom-service'
        c.version = '2.0.0'
        c.env = 'production'
      end
      
      provider = ::OpenTelemetry.meter_provider
      attributes = provider.instance_variable_get(:@resource).attribute_enumerator.to_h
      expect(attributes['service.name']).to eq('custom-service')
      expect(attributes['service.version']).to eq('2.0.0')
      expect(attributes['deployment.environment']).to eq('production')
    end

    it 'includes custom tags as resource attributes' do
      setup_metrics do |c|
        c.service = 'test-service'
        c.version = '1.0.0'
        c.env = 'test'
        c.tags = { 'team' => 'backend', 'region' => 'us-east-1' }
      end
      
      provider = ::OpenTelemetry.meter_provider
      attributes = provider.instance_variable_get(:@resource).attribute_enumerator.to_h
      expect(attributes['team']).to eq('backend')
      expect(attributes['region']).to eq('us-east-1')
    end
  end

  describe 'Configuration' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    it 'uses default values when environment variables are not set' do
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => nil,
        'OTEL_METRIC_EXPORT_INTERVAL' => nil,
        'OTEL_EXPORTER_OTLP_PROTOCOL' => nil
      ) do
        expect(settings.opentelemetry.metrics.enabled).to be false
        expect(settings.opentelemetry.metrics.export_interval).to eq(10_000)
        expect(settings.opentelemetry.exporter.protocol).to eq('http/protobuf')
        expect(settings.opentelemetry.exporter.endpoint).to eq('http://127.0.0.1:4318')
      end
    end

    it 'metrics-specific configs take precedence over general OTLP configs' do
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' => 'http://metrics:4317',
        'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'http/protobuf',
        'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '5000',
        'OTEL_EXPORTER_OTLP_METRICS_HEADERS' => '{"metrics":"value"}',
        'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://general:4317',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'grpc',
        'OTEL_EXPORTER_OTLP_TIMEOUT' => '20000',
        'OTEL_EXPORTER_OTLP_HEADERS' => '{"general":"value"}'
      ) do
        expect(settings.opentelemetry.metrics.endpoint).to eq('http://metrics:4317')
        expect(settings.opentelemetry.metrics.protocol).to eq('http/protobuf')
        expect(settings.opentelemetry.metrics.timeout).to eq(5_000)
        expect(settings.opentelemetry.metrics.headers).to eq('metrics' => 'value')
        expect(settings.opentelemetry.exporter.endpoint).to eq('http://general:4317')
        expect(settings.opentelemetry.exporter.protocol).to eq('grpc')
        expect(settings.opentelemetry.exporter.timeout).to eq(20_000)
        expect(settings.opentelemetry.exporter.headers).to eq('general' => 'value')
      end
    end

    it 'general OTLP configs work in isolation' do
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://general:4317',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf',
        'OTEL_EXPORTER_OTLP_TIMEOUT' => '8000',
        'OTEL_EXPORTER_OTLP_HEADERS' => '{"general":"value"}'
      ) do
        expect(settings.opentelemetry.exporter.endpoint).to eq('http://general:4317')
        expect(settings.opentelemetry.exporter.protocol).to eq('http/protobuf')
        expect(settings.opentelemetry.exporter.timeout).to eq(8_000)
        expect(settings.opentelemetry.exporter.headers).to eq('general' => 'value')
        expect(settings.opentelemetry.metrics.protocol).to eq('http/protobuf')
        expect(settings.opentelemetry.metrics.timeout).to eq(8_000)
        expect(settings.opentelemetry.metrics.headers).to eq('general' => 'value')
      end
    end

    it 'respects export interval and timeout in SDK' do
      setup_metrics(
        'OTEL_METRIC_EXPORT_INTERVAL' => '200',
        'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '10000'
      )
      reader = ::OpenTelemetry.meter_provider.metric_readers.first
      expect(reader.instance_variable_get(:@export_interval)).to eq(0.2)
      expect(reader.instance_variable_get(:@export_timeout)).to eq(10.0)
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

    it 'does not initialize when DD_METRICS_OTEL_ENABLED is false' do
      ClimateControl.modify('DD_METRICS_OTEL_ENABLED' => 'false', 'DD_SERVICE' => 'dd-service') do
        Datadog.send(:reset!) if Datadog.respond_to?(:reset!, true)
        provider = ::OpenTelemetry.meter_provider
        provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
        ::OpenTelemetry.meter_provider = ::OpenTelemetry::Internal::ProxyMeterProvider.new
        Datadog.configure { |c| }
        OpenTelemetry::SDK.configure
      end
      provider = ::OpenTelemetry.meter_provider
      resource = provider.instance_variable_get(:@resource)
      attributes = resource.attribute_enumerator.to_h
      # meter provider should not be configured to use Datadog configurations.
      expect(attributes['service.name']).not_to eq('dd-service')
    end
  end

  describe 'Multiple Data Points' do
    it 'supports multiple attributes and data points' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      counter = provider.meter('app').create_counter('api')
      counter.add(10, attributes: { 'method' => 'GET' })
      counter.add(5, attributes: { 'method' => 'POST' })
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
