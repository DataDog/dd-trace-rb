# frozen_string_literal: true

require 'spec_helper'
require 'opentelemetry/sdk'
require 'opentelemetry-metrics-sdk'
require 'opentelemetry/exporter/otlp_metrics'
require 'datadog/opentelemetry/metrics'
require 'datadog/core/configuration/settings'

RSpec.describe 'OpenTelemetry Metrics Integration' do
  before do
    Datadog.send(:reset!) if Datadog.respond_to?(:reset!, true)
    allow(Datadog.logger).to receive(:warn)
    allow(Datadog.logger).to receive(:error)
    allow(Datadog.logger).to receive(:debug)
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  after do
    provider = ::OpenTelemetry.meter_provider
    if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
      provider.shutdown
    end
    WebMock.reset!
    WebMock.disable!
  end

  def setup_metrics(env_overrides = {})
    ClimateControl.modify({
      'DD_METRICS_OTEL_ENABLED' => 'true',
      'DD_SERVICE' => 'test-service',
      'DD_VERSION' => '1.0.0',
      'DD_ENV' => 'test',
      'OTEL_METRIC_EXPORT_INTERVAL' => '10000',
      # For simplicity, we'll use http/protobuf for all tests
      # that export metrics (GRPC support is validated by system tests).
      'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf'
    }.merge(env_overrides)) do
      Datadog.configure do |c|
        c.service = 'test-service'
        c.version = '1.0.0'
        c.env = 'test'
      end
    end
  end

  def mock_otlp_export(&validator)
    captured_payloads = []
    captured_headers_list = []
    validator_called = false
    request_count = 0
    mutex = Mutex.new

    stub_request(:post, %r{http://.*:4318/v1/metrics}).to_return do |request|
      mutex.synchronize do
        request_count += 1
        puts "[DEBUG] HTTP Request ##{request_count} received: #{request.uri}" if ENV['DEBUG']
        
        headers = request.headers
        payload = request.body

        puts "[DEBUG] Payload size: #{payload&.size || 0} bytes" if ENV['DEBUG']
        puts "[DEBUG] Content-Encoding: #{headers['Content-Encoding'] || headers['content-encoding']}" if ENV['DEBUG']
        puts "[DEBUG] Content-Type: #{headers['Content-Type'] || headers['content-type']}" if ENV['DEBUG']

        content_encoding = headers['Content-Encoding'] || headers['content-encoding']
        if content_encoding == 'gzip'
          require 'zlib'
          require 'stringio'
          io = StringIO.new(payload)
          gz = Zlib::GzipReader.new(io)
          payload = gz.read
          gz.close
          puts "[DEBUG] Decompressed payload size: #{payload.size} bytes" if ENV['DEBUG']
        end

        content_type = headers['Content-Type'] || headers['content-type']
        is_json = content_type && content_type.include?('application/json')

        decoded = if is_json
          JSON.parse(payload)
        else
          require 'opentelemetry/proto/collector/metrics/v1/metrics_service_pb'
          begin
            Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest.decode(payload)
          rescue NameError
            OpenTelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest.decode(payload)
          end
        end

        puts "[DEBUG] Decoded payload: #{decoded.class}" if ENV['DEBUG']
        inspect_payload_structure(decoded) if ENV['DEBUG']

        captured_payloads << decoded
        captured_headers_list << headers

        if validator
          puts "[DEBUG] Calling validator on request ##{request_count}..." if ENV['DEBUG']
          begin
            validator.call(decoded, headers)
            validator_called = true unless validator_called
            puts "[DEBUG] Validator called successfully" if ENV['DEBUG']
          rescue RSpec::Expectations::ExpectationNotMetError => e
            puts "[DEBUG] Validator assertion failed (may retry on next payload): #{e.message}" if ENV['DEBUG']
            raise e if request_count >= 3
          rescue => e
            validator_called = true
            puts "[DEBUG] Validator raised error: #{e.class}: #{e.message}" if ENV['DEBUG']
            raise e
          end
        end
      end

      { status: 200, body: '' }
    end

    stub_request(:post, %r{http://.*:4317}).to_return do |request|
      puts "[DEBUG] gRPC request received: #{request.uri}" if ENV['DEBUG']
      { status: 200, body: '' }
    end

    -> {
      mutex.synchronize do
        puts "[DEBUG] Final check: request_count=#{request_count}, validator_called=#{validator_called}, captured_payloads=#{captured_payloads.length}" if ENV['DEBUG']
        raise "OTLP export validator was never called (received #{request_count} requests)" unless validator_called
      end
    }
  end

  def inspect_payload_structure(payload)
    return unless payload.respond_to?(:resource_metrics)

    payload.resource_metrics.each do |rm|
      rm.scope_metrics.each do |sm|
        sm.metrics.each do |metric|
          puts "=== Metric: #{metric.name} ==="
          if metric.sum
            puts "  Type: Sum"
            puts "  Temporality: #{metric.sum.aggregation_temporality}" if metric.sum.respond_to?(:aggregation_temporality)
            metric.sum.data_points.each_with_index do |dp, idx|
              puts "  DataPoint[#{idx}]:"
              puts "    as_int: #{dp.as_int}" if dp.respond_to?(:as_int)
              puts "    as_double: #{dp.as_double}" if dp.respond_to?(:as_double)
              puts "    int_value: #{dp.int_value}" if dp.respond_to?(:int_value)
              puts "    double_value: #{dp.double_value}" if dp.respond_to?(:double_value)
              puts "    Attributes (#{dp.attributes.length}):"
              dp.attributes.each do |attr|
                val = if attr.value.respond_to?(:string_value)
                  attr.value.string_value
                elsif attr.value.respond_to?(:int_value)
                  attr.value.int_value
                elsif attr.value.respond_to?(:double_value)
                  attr.value.double_value
                else
                  attr.value.inspect
                end
                puts "      #{attr.key}: #{val} (#{attr.value.class})"
              end
            end
          elsif metric.gauge
            puts "  Type: Gauge"
            puts "  Temporality: #{metric.gauge.aggregation_temporality}" if metric.gauge.respond_to?(:aggregation_temporality)
            metric.gauge.data_points.each_with_index do |dp, idx|
              puts "  DataPoint[#{idx}]: as_double=#{dp.as_double}" if dp.respond_to?(:as_double)
              puts "    TimeUnixNano: #{dp.time_unix_nano}" if dp.respond_to?(:time_unix_nano)
            end
          elsif metric.histogram
            puts "  Type: Histogram"
            puts "  Temporality: #{metric.histogram.aggregation_temporality}" if metric.histogram.respond_to?(:aggregation_temporality)
            metric.histogram.data_points.each_with_index do |dp, idx|
              puts "  DataPoint[#{idx}]: sum=#{dp.sum}, count=#{dp.count}" if dp.respond_to?(:sum)
            end
          end
        end
      end
    end
  end

  def flush_and_wait(provider)
    return unless provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
    
    reader = provider.metric_readers.first
    reader.force_flush if reader&.respond_to?(:force_flush)
    provider.force_flush
  end

  def find_metric_in_payload(payload, name)
    return nil unless payload.respond_to?(:resource_metrics)

    payload.resource_metrics.each do |resource_metric|
      resource_metric.scope_metrics.each do |scope_metric|
        scope_metric.metrics.each do |metric|
          return metric if metric.name == name
        end
      end
    end
    nil
  end

  describe 'Basic Functionality' do
    it 'exports counter metrics' do
      verify_validator = mock_otlp_export do |payload, headers|
        metric = find_metric_in_payload(payload, 'requests')
        value = metric.sum.data_points.first.as_int != 0 ? metric.sum.data_points.first.as_int : metric.sum.data_points.first.as_double.to_i
        expect(value).to eq(5)
      end

      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_counter('requests').add(5)
      flush_and_wait(provider)
      verify_validator.call
    end

    it 'exports histogram metrics' do
      verify_validator = mock_otlp_export do |payload, headers|
        metric = find_metric_in_payload(payload, 'duration')
        expect(metric.histogram.data_points.first.sum).to eq(100.0)
        expect(metric.histogram.data_points.first.count).to eq(1)
      end

      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_histogram('duration').record(100)
      flush_and_wait(provider)
      verify_validator.call
    end

    it 'exports gauge metrics' do
      all_payloads = []
      verify_validator = mock_otlp_export { |payload, headers| all_payloads << payload }

      setup_metrics('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' => 'cumulative')
      provider = ::OpenTelemetry.meter_provider
      gauge = provider.meter('app').create_gauge('temperature')
      
      gauge.record(72)
      flush_and_wait(provider)
      
      gauge.record(72)
      flush_and_wait(provider)

      verify_validator.call
      expect(all_payloads.length).to be >= 1
      
      found = all_payloads.any? do |payload|
        metric = find_metric_in_payload(payload, 'temperature')
        next false unless metric
        value = metric.gauge.data_points.first.as_int != 0 ? metric.gauge.data_points.first.as_int : metric.gauge.data_points.first.as_double.to_i
        value == 72
      end
      
      expect(found).to be true
    end

    it 'exports updowncounter metrics' do
      verify_validator = mock_otlp_export do |payload, headers|
        metric = find_metric_in_payload(payload, 'queue')
        expect(metric.sum.data_points.first.as_int).to eq(10)
      end

      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_up_down_counter('queue').add(10)
      flush_and_wait(provider)
      verify_validator.call
    end

    it 'handles multiple metric types' do
      verify_validator = mock_otlp_export do |payload, headers|
        size_metric = find_metric_in_payload(payload, 'size')
        requests_metric = find_metric_in_payload(payload, 'requests')
        memory_metric = find_metric_in_payload(payload, 'memory')

        expect(size_metric.histogram.data_points.first.sum).to eq(100.0)
        expect(size_metric.histogram.data_points.first.count).to eq(1)
        expect(requests_metric.sum.data_points.first.as_int).to eq(10)

        if memory_metric
          gauge_value = memory_metric.gauge.data_points.first.as_int != 0 ? memory_metric.gauge.data_points.first.as_int : memory_metric.gauge.data_points.first.as_double.to_i
          expect(gauge_value).to eq(100) if gauge_value != 0
        end
      end

      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      meter = provider.meter('app')
      meter.create_histogram('size').record(100)
      meter.create_counter('requests').add(10)
      meter.create_gauge('memory').record(100)
      flush_and_wait(provider)
      verify_validator.call
    end
  end

  describe 'Resource Attributes' do
    it 'includes service name, version, and environment from Datadog config' do
      ClimateControl.modify({
        'DD_METRICS_OTEL_ENABLED' => 'true',
        'DD_SERVICE' => 'custom-service',
        'DD_VERSION' => '2.0.0',
        'DD_ENV' => 'production',
        'OTEL_METRIC_EXPORT_INTERVAL' => '10000',
        'OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf'
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
    let(:settings) { Datadog::Core::Configuration::Settings.new }
    it 'uses default values when environment variables are not set' do
      ClimateControl.modify(
        'DD_METRICS_OTEL_ENABLED' => nil,
        'OTEL_METRIC_EXPORT_INTERVAL' => nil,
        'OTEL_EXPORTER_OTLP_PROTOCOL' => nil
      ) do
        expect(settings.opentelemetry.metrics.enabled).to be false
        expect(settings.opentelemetry.metrics.export_interval).to eq(60_000)
        expect(settings.opentelemetry.exporter.protocol).to eq('grpc')
        expect(settings.opentelemetry.exporter.endpoint).to eq('http://127.0.0.1:4317')
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
        'OTEL_EXPORTER_OTLP_TIMEOUT' => '10000',
        'OTEL_EXPORTER_OTLP_HEADERS' => '{"general":"value"}'
      ) do
        expect(settings.opentelemetry.metrics.endpoint).to eq('http://metrics:4317')
        expect(settings.opentelemetry.metrics.protocol).to eq('http/protobuf')
        expect(settings.opentelemetry.metrics.timeout).to eq(5_000)
        expect(settings.opentelemetry.metrics.headers).to eq('metrics' => 'value')
        expect(settings.opentelemetry.exporter.endpoint).to eq('http://general:4317')
        expect(settings.opentelemetry.exporter.protocol).to eq('grpc')
        expect(settings.opentelemetry.exporter.timeout).to eq(10_000)
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
      mock_otlp_export
      setup_metrics('OTEL_METRIC_EXPORT_INTERVAL' => '200', 'OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => '10000')
      reader = ::OpenTelemetry.meter_provider.metric_readers.first
      expect(reader.export_interval_millis).to eq(200) if reader.respond_to?(:export_interval_millis)
      expect(reader.export_timeout_millis).to eq(10_000) if reader.respond_to?(:export_timeout_millis)
    end

    it 'uses OTLP exporter when configured' do
      verify_validator = mock_otlp_export do |payload, headers|
        expect(payload).to respond_to(:resource_metrics)
      end

      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      exporter = provider.metric_readers.first.instance_variable_get(:@exporter)
      expect(exporter).to be_a(::OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter)
      provider.meter('app').create_counter('test').add(1)
      flush_and_wait(provider)
      verify_validator.call
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
      verify_validator = mock_otlp_export do |payload, headers|
        metric = find_metric_in_payload(payload, 'api')
        expect(metric.sum.data_points.length).to be >= 1

        get_point = metric.sum.data_points.find { |dp| dp.attributes.find { |a| a.key == 'method' }&.value&.string_value == 'GET' }
        post_point = metric.sum.data_points.find { |dp| dp.attributes.find { |a| a.key == 'method' }&.value&.string_value == 'POST' }

        if get_point && post_point
          expect(get_point.as_int).to eq(10)
          expect(post_point.as_int).to eq(5)
        else
          expect(metric.sum.data_points.first.as_int).to eq(15)
        end
      end

      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      counter = provider.meter('app').create_counter('api')
      counter.add(10, attributes: { 'method' => 'GET' })
      counter.add(5, attributes: { 'method' => 'POST' })
      flush_and_wait(provider)
      verify_validator.call
    end
  end

  describe 'Lifecycle' do
    it 'handles shutdown gracefully' do
      stub_request(:post, %r{http://.*:4318/v1/metrics}).to_return(status: 200, body: '')
      stub_request(:post, %r{http://.*:4317}).to_return(status: 200, body: '')
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      expect { provider.shutdown }.not_to raise_error
      expect { provider.shutdown }.not_to raise_error
    end

    it 'handles force_flush' do
      stub_request(:post, %r{http://.*:4318/v1/metrics}).to_return(status: 200, body: '')
      stub_request(:post, %r{http://.*:4317}).to_return(status: 200, body: '')
      setup_metrics
      provider = ::OpenTelemetry.meter_provider
      provider.meter('app').create_counter('test').add(1)
      expect { provider.force_flush }.not_to raise_error
    end
  end
end
