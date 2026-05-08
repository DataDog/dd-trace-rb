# frozen_string_literal: true

require 'spec_helper'

# OpenTelemetry logs SDK requires Ruby >= 3.1
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1')
  require 'opentelemetry/sdk'
  require 'opentelemetry-logs-sdk'
  require 'opentelemetry/exporter/otlp_logs'
end

require 'datadog/opentelemetry'
require 'datadog/core/configuration/settings'
require 'net/http'
require 'json'

RSpec.describe 'OpenTelemetry Logs Integration', ruby: '>= 3.1' do
  let(:default_otlp_http_port) { 4318 }
  let(:provider) { ::OpenTelemetry.logger_provider }
  let(:processor) { provider.instance_variable_get(:@log_record_processors)&.first }
  let(:exporter) { processor&.instance_variable_get(:@exporter) }
  let(:resource) { provider.instance_variable_get(:@resource) }
  let(:attributes) { resource.attribute_enumerator.to_h }
  let(:logs_settings) { Datadog.configuration.opentelemetry.logs }

  before do
    clear_testagent_logs
  end

  after do
    provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Logs::LoggerProvider)
  end

  def agent_host
    Datadog.send(:components).agent_settings.hostname
  end

  def clear_testagent_logs
    uri = URI("http://#{agent_host}:#{default_otlp_http_port}/test/session/clear")
    Net::HTTP.post_form(uri, {})
  rescue => e
    raise "Error clearing testagent logs: #{e.class}: #{e}"
  end

  def get_testagent_logs
    uri = URI("http://#{agent_host}:#{default_otlp_http_port}/test/session/logs")

    try_wait_until(seconds: 2) do
      response = Net::HTTP.get_response(uri)
      next unless response.code == '200'

      parsed = JSON.parse(response.body, symbolize_names: false)
      next parsed if parsed.is_a?(Array) && !parsed.empty?
    end
  end

  def find_log_record(body_text)
    get_testagent_logs.each do |payload|
      payload['resource_logs']&.each do |rl|
        rl['scope_logs']&.each do |sl|
          sl['log_records']&.each do |record|
            text = record.dig('body', 'string_value') || record.dig('body', 'value', 'string_value')
            return record if text&.include?(body_text)
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

  def setup_logs(env_overrides = {}, &config_block)
    ClimateControl.modify({
      'DD_LOGS_OTEL_ENABLED' => 'true',
      'DD_AGENT_HOST' => agent_host,
    }.merge(env_overrides)) do
      Datadog.send(:reset!)
      Datadog.configure do |c|
        config_block&.call(c)
      end
      OpenTelemetry::SDK.configure
    end
  end

  describe 'Basic Functionality' do
    it 'exports a log record' do
      setup_logs
      logger = provider.logger(name: 'app')
      logger.on_emit(timestamp: Time.now, severity_number: 9, body: 'hello world')
      provider.force_flush

      record = find_log_record('hello world')
      expect(record).not_to be_nil
      expect(record.dig('body', 'string_value')).to include('hello world')
    end

    it 'exports log records with attributes' do
      setup_logs
      logger = provider.logger(name: 'app')
      logger.on_emit(
        timestamp: Time.now,
        severity_number: 9,
        body: 'structured log',
        attributes: {'user.id' => '42', 'http.method' => 'GET'}
      )
      provider.force_flush

      record = find_log_record('structured log')
      expect(record).not_to be_nil
    end
  end

  describe 'Resource Attributes' do
    it 'includes service name, version, and environment from Datadog config' do
      setup_logs(
        'DD_SERVICE' => 'custom-service',
        'DD_VERSION' => '2.0.0',
        'DD_ENV' => 'production',
        'DD_TRACE_REPORT_HOSTNAME' => 'true',
      )

      expect(attributes['service.name']).to eq('custom-service')
      expect(attributes['service.version']).to eq('2.0.0')
      expect(attributes['deployment.environment']).to eq('production')
      expect(attributes['host.name']).to eq(Datadog::Core::Environment::Socket.hostname)
    end

    it 'does not include host.name when report_hostname is false' do
      setup_logs('DD_TRACE_REPORT_HOSTNAME' => 'false')
      expect(attributes['host.name']).to be_nil
    end

    it 'uses DD_HOSTNAME as host.name when report_hostname is true' do
      setup_logs('DD_TRACE_REPORT_HOSTNAME' => 'true', 'DD_HOSTNAME' => 'custom-host')
      expect(attributes['host.name']).to eq('custom-host')
    end

    it 'falls back to Socket.hostname when DD_HOSTNAME is not set and report_hostname is true' do
      setup_logs('DD_TRACE_REPORT_HOSTNAME' => 'true')
      expect(attributes['host.name']).to eq(Datadog::Core::Environment::Socket.hostname)
    end

    it 'DD_HOSTNAME takes precedence over host.name set via tags when report_hostname is true' do
      setup_logs('DD_TRACE_REPORT_HOSTNAME' => 'true', 'DD_HOSTNAME' => 'explicit-host') do |c|
        c.tags = {'host.name' => 'tag-host'}
      end
      expect(attributes['host.name']).to eq('explicit-host')
    end

    it 'preserves host.name from tags when DD_HOSTNAME is not set and report_hostname is true' do
      setup_logs('DD_TRACE_REPORT_HOSTNAME' => 'true') do |c|
        c.tags = {'host.name' => 'tag-host'}
      end
      expect(attributes['host.name']).to eq('tag-host')
    end

    it 'includes custom tags as resource attributes' do
      setup_logs('DD_SERVICE' => 'unused-name', 'DD_ENV' => 'unused-env', 'DD_VERSION' => 'x.y.z') do |c|
        c.service = 'test-service'
        c.version = '1.0.0'
        c.env = 'test'
        c.tags = {'team' => 'backend', 'region' => 'us-east-1', 'host.name' => 'myhost'}
        c.tracing.report_hostname = true
      end

      expect(attributes['service.name']).to eq('test-service')
      expect(attributes['service.version']).to eq('1.0.0')
      expect(attributes['deployment.environment']).to eq('test')
      expect(attributes['host.name']).to eq('myhost')
      expect(attributes['team']).to eq('backend')
      expect(attributes['region']).to eq('us-east-1')
    end

    it 'applies fallback service name when neither DD_SERVICE nor service tag is set' do
      setup_logs
      expect(attributes['service.name']).to eq(Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME)
    end
  end

  describe 'Trace Context' do
    # OpenTelemetry logs read trace context from OpenTelemetry::Context; Datadog uses its own
    # context. A bridge to set OTel context from the active Datadog span is not yet implemented.
    it 'includes trace_id and span_id when emitting inside an active Datadog span', pending: 'OTel logs use OpenTelemetry::Context; Datadog span context bridge not implemented' do
      setup_logs
      trace_id = nil
      span_id = nil

      Datadog::Tracing.trace('test.op') do |span|
        trace_id = format('%032x', span.trace_id)
        span_id = format('%016x', span.id)
        provider.logger(name: 'app').on_emit(timestamp: Time.now, severity_number: 9, body: 'inside-span')
        provider.force_flush
      end

      record = find_log_record('inside-span')
      expect(record).not_to be_nil
      expect(record['trace_id']).to eq(trace_id)
      expect(record['span_id']).to eq(span_id)
    end
  end

  describe 'Log Injection' do
    it 'disables Datadog log injection after provider setup' do
      setup_logs
      expect(Datadog.configuration.tracing.log_injection).to be(false)
    end
  end

  describe 'Configuration' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    describe 'default values' do
      before { setup_logs }

      it 'uses default HTTP endpoint' do
        expect(exporter.instance_variable_get(:@uri).to_s).to eq("http://#{agent_host}:4318/v1/logs")
      end

      it 'uses default timeout' do
        expect(exporter.instance_variable_get(:@timeout)).to eq(10.0)
      end
    end

    describe 'configuration priority' do
      let(:env_vars) do
        {
          'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://general:4317',
          'OTEL_EXPORTER_OTLP_TIMEOUT' => '8000',
          'OTEL_EXPORTER_OTLP_HEADERS' => 'general=value'
        }
      end

      before { setup_logs(env_vars) }

      it 'uses the general OTLP endpoint' do
        expect(exporter.instance_variable_get(:@uri).to_s).to eq('http://general:4317/v1/logs')
      end

      it 'uses the general OTLP timeout' do
        expect(exporter.instance_variable_get(:@timeout)).to eq(8.0)
      end

      it 'uses the general OTLP headers' do
        expect(exporter.instance_variable_get(:@headers)['general']).to eq('value')
      end

      context 'when logs-specific configs are provided' do
        let(:env_vars) do
          super().merge(
            'DD_LOGS_OTEL_ENABLED' => 'true',
            'OTEL_EXPORTER_OTLP_LOGS_ENDPOINT' => 'http://logs:4318/v1/logs',
            'OTEL_EXPORTER_OTLP_LOGS_TIMEOUT' => '5000',
            'OTEL_EXPORTER_OTLP_LOGS_HEADERS' => 'logs=value',
          )
        end

        it 'uses logs-specific endpoint' do
          expect(exporter.instance_variable_get(:@uri).to_s).to eq('http://logs:4318/v1/logs')
        end

        it 'uses logs-specific timeout' do
          expect(exporter.instance_variable_get(:@timeout)).to eq(5.0)
        end

        it 'uses logs-specific headers' do
          expect(exporter.instance_variable_get(:@headers)['logs']).to eq('value')
        end
      end
    end

    it 'parses multiple headers correctly' do
      setup_logs(
        'OTEL_EXPORTER_OTLP_HEADERS' => 'api-key=secret123,other-config-value=test-value'
      )
      headers = exporter.instance_variable_get(:@headers)
      expect(headers['api-key']).to eq('secret123')
      expect(headers['other-config-value']).to eq('test-value')
    end

    it 'returns empty hash when headers are malformed' do
      setup_logs(
        'OTEL_EXPORTER_OTLP_LOGS_HEADERS' => 'api-key=secret123,malformed'
      )
      expect(logs_settings.headers).to eq({})
    end

    it 'returns empty hash when header has empty key or value' do
      setup_logs(
        'OTEL_EXPORTER_OTLP_LOGS_HEADERS' => 'api-key=secret123,=value'
      )
      expect(logs_settings.headers).to eq({})
    end

    it 'normalizes invalid protocol to http/protobuf' do
      setup_logs(
        'OTEL_EXPORTER_OTLP_LOGS_PROTOCOL' => 'invalid'
      )
      expect(logs_settings.protocol).to eq('http/protobuf')
    end

    it 'accepts http/json protocol' do
      setup_logs(
        'OTEL_EXPORTER_OTLP_LOGS_PROTOCOL' => 'http/json'
      )
      expect(logs_settings.protocol).to eq('http/json')
    end

    it 'does not initialize when DD_LOGS_OTEL_ENABLED is false' do
      setup_logs('DD_LOGS_OTEL_ENABLED' => 'false', 'DD_SERVICE' => 'dd-service')
      # When disabled, our LoggerProvider is not set; global remains ProxyLoggerProvider
      expect(provider).not_to be_a(::OpenTelemetry::SDK::Logs::LoggerProvider)
    end
  end

  describe 'Lifecycle' do
    it 'handles shutdown gracefully' do
      setup_logs
      expect { provider.shutdown }.not_to raise_error
      expect { provider.shutdown }.not_to raise_error
    end

    it 'handles force_flush' do
      setup_logs
      provider.logger(name: 'app').on_emit(timestamp: Time.now, severity_number: 9, body: 'flush test')
      expect { provider.force_flush }.not_to raise_error
    end
  end
end
