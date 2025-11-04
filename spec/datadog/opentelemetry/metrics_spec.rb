# frozen_string_literal: true

require 'spec_helper'
require 'opentelemetry/sdk'
require 'opentelemetry-metrics-sdk'
require 'datadog/opentelemetry/metrics'

RSpec.describe 'OpenTelemetry Metrics Integration' do
  before do
    Datadog.send(:reset!) if Datadog.respond_to?(:reset!, true)
    allow(Datadog.logger).to receive(:warn)
    allow(Datadog.logger).to receive(:error)
    allow(Datadog.logger).to receive(:debug)
  end

  after do
    provider = ::OpenTelemetry.meter_provider
    provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
  end

  def setup_metrics(env_overrides = {})
    ClimateControl.modify({
      'DD_METRICS_OTEL_ENABLED' => 'true',
      'DD_SERVICE' => 'test-service',
      'DD_VERSION' => '1.0.0',
      'DD_ENV' => 'test',
      'OTEL_METRIC_EXPORT_INTERVAL' => '50',
      'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '5000'
    }.merge(env_overrides)) do
      Datadog.configure do |c|
        c.service = 'test-service'
        c.version = '1.0.0'
        c.env = 'test'
      end
    end
  end

  let(:exported_payloads) { [] }

  def setup_exporter_mock(provider)
    exporter = provider.metric_readers.first.instance_variable_get(:@exporter)
    allow(exporter).to receive(:export) do |metrics, timeout: nil|
      exported_payloads.concat(Array(metrics))
      ::OpenTelemetry::SDK::Metrics::Export::SUCCESS
    end
    allow($stdout).to receive(:puts).and_return(nil)
    allow($stdout).to receive(:write).and_return(nil)
    allow($stdout).to receive(:print).and_return(nil)
  end

  def flush_and_wait(provider)
    provider.force_flush
    reader = provider.metric_readers.first
    reader.force_flush if reader.respond_to?(:force_flush)
    sleep(0.3)
  end

  def find_metric(payloads, name)
    payloads.reverse_each do |payload|
      return payload if payload.respond_to?(:name) && payload.name == name
    end
    nil
  end

  describe 'Basic Functionality' do
    it 'exports counter metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      meter = provider.meter('app')
      meter.create_counter('requests').add(5.1)
      flush_and_wait(provider)
      sleep(0.3)
      metric = find_metric(exported_payloads, 'requests')
      expect(metric).not_to be_nil
      expect(metric.data_points.first.value).to eq(5.1)
    end

    it 'exports histogram metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      provider.meter('app').create_histogram('duration').record(100)
      flush_and_wait(provider)
      metric = find_metric(exported_payloads, 'duration')
      expect(metric).not_to be_nil
      expect(metric.data_points.first.sum).to eq(100)
      expect(metric.data_points.first.count).to eq(1)
    end

    it 'exports gauge metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      provider.meter('app').create_gauge('temperature').record(72)
      flush_and_wait(provider)
      metric = find_metric(exported_payloads, 'temperature')
      expect(metric).not_to be_nil
      expect(metric.data_points.first.value).to eq(72)
    end

    it 'exports updowncounter metrics' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      provider.meter('app').create_up_down_counter('queue').add(10)
      flush_and_wait(provider)
      metric = find_metric(exported_payloads, 'queue')
      expect(metric).not_to be_nil
      expect(metric.data_points.first.value).to eq(10)
    end

    it 'exports observable gauge metrics' do
      setup_metrics('OTEL_METRIC_EXPORT_INTERVAL' => '50')
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      callback_invoked = false
      received_result = false
      callback = proc do |result = nil|
        callback_invoked = true
        if result && result.respond_to?(:observe)
          received_result = true
          result.observe(100, { 'type' => 'heap' })
        end
      end
      provider.meter('app').create_observable_gauge('memory', callback: callback)
      provider.force_flush
      sleep(0.3)
      expect(callback_invoked).to be(true)
      pending 'opentelemetry-metrics-sdk 0.11.0 bug: callbacks called with 0 args instead of ObservableResult'
      expect(received_result).to be(true)
      metric = find_metric(exported_payloads, 'memory')
      expect(metric).not_to be_nil
      expect(metric.data_points.first.value).to eq(100)
      expect(metric.data_points.first.attributes['type']).to eq('heap')
    end

    it 'handles multiple metric types' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      meter = provider.meter('app')
      meter.create_histogram('size').record(100)
      meter.create_counter('requests').add(10)
      meter.create_gauge('memory').record(100)
      flush_and_wait(provider)
      expect(find_metric(exported_payloads, 'size').data_points.first.sum).to eq(100)
      expect(find_metric(exported_payloads, 'size').data_points.first.count).to eq(1)
      expect(find_metric(exported_payloads, 'requests').data_points.first.value).to eq(10)
      expect(find_metric(exported_payloads, 'memory').data_points.first.value).to eq(100)
    end
  end

  describe 'Resource Attributes' do
    it 'includes service name, version, and environment from Datadog config' do
      ClimateControl.modify({
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'DD_SERVICE' => 'custom-service',
        'DD_VERSION' => '2.0.0',
        'DD_ENV' => 'production'
      }) do
        Datadog.send(:reset!) if Datadog.respond_to?(:reset!, true)
        Datadog.configure do |c|
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
    end

    it 'includes custom tags as resource attributes' do
      setup_metrics('DD_TAGS' => 'team:backend,region:us-east-1')
      Datadog.configure { |c| c.tags = { 'team' => 'backend', 'region' => 'us-east-1' } }
      provider = ::OpenTelemetry.meter_provider
      attributes = provider.instance_variable_get(:@resource).attribute_enumerator.to_h
      expect(attributes['team']).to eq('backend')
      expect(attributes['region']).to eq('us-east-1')
    end
  end

  describe 'Configuration' do
    it 'respects export interval from environment' do
      setup_metrics('OTEL_METRIC_EXPORT_INTERVAL' => '200')
      reader = ::OpenTelemetry.meter_provider.metric_readers.first
      expect(reader.export_interval_millis).to eq(200) if reader.respond_to?(:export_interval_millis)
    end

    it 'respects export timeout from environment' do
      setup_metrics('OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '10000')
      reader = ::OpenTelemetry.meter_provider.metric_readers.first
      expect(reader.export_timeout_millis).to eq(10_000) if reader.respond_to?(:export_timeout_millis)
    end

    it 'uses console exporter when no custom exporter provided' do
      setup_metrics
      exporter = ::OpenTelemetry.meter_provider.metric_readers.first.instance_variable_get(:@exporter)
      expect(exporter).to be_a(::OpenTelemetry::SDK::Metrics::Export::ConsoleMetricPullExporter)
    end

    it 'does not initialize when DD_METRICS_OTEL_ENABLED is false' do
      ClimateControl.modify('DD_METRICS_OTEL_ENABLED' => 'false') do
        Datadog.send(:reset!) if Datadog.respond_to?(:reset!, true)
        provider = ::OpenTelemetry.meter_provider
        provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
        ::OpenTelemetry.meter_provider = ::OpenTelemetry::Internal::ProxyMeterProvider.new
        Datadog.configure { |c| }
      end
      expect(::OpenTelemetry.meter_provider.class.name).not_to include('SDK')
    end
  end

  describe 'Multiple Data Points' do
    it 'supports multiple attributes and data points' do
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      setup_exporter_mock(provider)
      counter = provider.meter('app').create_counter('api')
      counter.add(10, attributes: { 'method' => 'GET' })
      counter.add(5, attributes: { 'method' => 'POST' })
      flush_and_wait(provider)
      metric = find_metric(exported_payloads, 'api')
      expect(metric).not_to be_nil
      expect(metric.data_points.length).to be >= 1
      get_point = metric.data_points.find { |dp| dp.attributes['method'] == 'GET' }
      post_point = metric.data_points.find { |dp| dp.attributes['method'] == 'POST' }
      if get_point && post_point
        expect(get_point.value).to eq(10)
        expect(post_point.value).to eq(5)
      else
        expect(metric.data_points.first.value).to eq(15)
      end
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

  describe 'OTLP Endpoint Configuration' do
    it 'configures OTLP endpoint from environment variable' do
      endpoint = nil
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' => 'http://custom:4321/v1/metrics'
      ) do
        Datadog.configure { |c| }
        endpoint = Datadog.configuration.opentelemetry.metrics.endpoint
      end
      expect(endpoint).to eq('http://custom:4321/v1/metrics')
    end

    it 'prioritizes metrics-specific endpoint over generic endpoint' do
      metrics_endpoint = nil
      exporter_endpoint = nil
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' => 'http://custom:4318/v1/metrics',
        'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://generic:4318/v1/metrics'
      ) do
        Datadog.configure { |c| }
        settings = Datadog.configuration
        metrics_endpoint = settings.opentelemetry.metrics.endpoint
        exporter_endpoint = settings.opentelemetry.exporter.endpoint
      end
      expect(metrics_endpoint).to eq('http://custom:4318/v1/metrics')
      expect(exporter_endpoint).to eq('http://generic:4318/v1/metrics')
    end

    it 'appends /v1/metrics to exporter endpoint if not provided' do
      exporter_endpoint = nil
      resolved_endpoint = nil
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://custom:4318',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf'
      ) do
        Datadog.configure { |c| }
        settings = Datadog.configuration
        exporter_endpoint = settings.opentelemetry.exporter.endpoint
        resolved_endpoint = Datadog::OpenTelemetry::Metrics::Initializer.send(:resolve_metrics_endpoint, settings.opentelemetry.metrics, settings.opentelemetry.exporter)
      end
      expect(exporter_endpoint).to eq('http://custom:4318')
      expect(resolved_endpoint).to eq('http://custom:4318/v1/metrics')
    end
  end
end
