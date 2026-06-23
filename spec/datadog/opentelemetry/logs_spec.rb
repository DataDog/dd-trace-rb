# frozen_string_literal: true

require 'spec_helper'

# OpenTelemetry logs SDK requires Ruby >= 3.1
if RubyVersion.is?('>= 3.1')
  require 'opentelemetry/sdk'
  require 'opentelemetry-logs-sdk'
  require 'opentelemetry/exporter/otlp_logs'
end

require 'datadog/opentelemetry'
require 'datadog/opentelemetry/spec_helper'
require 'datadog/core/configuration/settings'
require 'net/http'
require 'json'

RSpec.describe 'OpenTelemetry Logs Integration', ruby: '>= 3.1' do
  let(:provider) { ::OpenTelemetry.logger_provider }
  let(:processor) { provider.instance_variable_get(:@log_record_processors)&.first }
  let(:exporter) { processor&.instance_variable_get(:@exporter) }
  let(:exporter_uri) { exporter.instance_variable_get(:@uri).to_s }
  let(:exporter_timeout) { exporter.instance_variable_get(:@timeout) }
  let(:exporter_headers) { exporter.instance_variable_get(:@headers) }
  let(:resource) { provider.instance_variable_get(:@resource) }
  let(:attributes) { resource.attribute_enumerator.to_h }
  let(:logs_settings) { Datadog.configuration.opentelemetry.logs }
  let(:agent_host) { Datadog.send(:components).agent_settings.hostname }
  let(:default_otlp_http_port) { 4318 }
  let(:testagent_base_uri) { "http://#{agent_host}:#{default_otlp_http_port}/test/session" }
  let(:env_overrides) { {} }
  let(:configuration) { nil }
  let(:logs_environment) do
    {
      'DD_LOGS_OTEL_ENABLED' => 'true',
      'DD_AGENT_HOST' => agent_host,
    }.merge(env_overrides)
  end

  before do
    ClimateControl.modify(logs_environment) do
      Datadog.send(:reset!)
      Datadog.configure do |c|
        configuration&.call(c)
      end
      OpenTelemetry::SDK.configure
    end

    # Clear trace agent log signals
    Net::HTTP.post_form(URI("#{testagent_base_uri}/clear"), {})
  end

  after do
    OpenTelemetryHelpers.shutdown_otel_providers
  end

  describe 'Basic Functionality' do
    let(:body_text) { 'hello world' }

    subject(:log_record) do
      try_wait_until(seconds: 2) do
        response = Net::HTTP.get_response(URI("#{testagent_base_uri}/logs"))
        next unless response.is_a?(Net::HTTPSuccess)

        logs = JSON.parse(response.body)
        next unless logs.is_a?(Array) && !logs.empty?

        logs
          .flat_map { |entry| Array(entry['resource_logs']) }
          .flat_map { |log| Array(log['scope_logs']) }
          .flat_map { |scope_log| Array(scope_log['log_records']) }
          .find do |record|
            text = record.dig('body', 'string_value') || record.dig('body', 'value', 'string_value')
            text&.include?(body_text)
          end
      end
    end

    context 'when a log record is emitted' do
      before do
        provider.logger(name: 'app').on_emit(timestamp: Time.now, severity_number: 9, body: body_text)
        provider.force_flush
      end

      it 'exports the log record' do
        expect(log_record).not_to be_nil
        expect(log_record.dig('body', 'string_value')).to include(body_text)
      end
    end
  end

  describe 'Resource Attributes' do
    subject(:resource_attributes) { attributes }
    context 'with service metadata provided by environment variables' do
      let(:env_overrides) do
        {
          'DD_SERVICE' => 'custom-service',
          'DD_VERSION' => '2.0.0',
          'DD_ENV' => 'production',
          'DD_TRACE_REPORT_HOSTNAME' => 'true',
        }
      end

      it 'includes service name, version, and environment from Datadog config' do
        expect(resource_attributes).to include(
          'service.name' => 'custom-service',
          'service.version' => '2.0.0',
          'deployment.environment' => 'production',
          'host.name' => Datadog::Core::Environment::Socket.hostname,
        )
      end
    end

    context 'when hostname reporting is disabled' do
      let(:env_overrides) { {'DD_TRACE_REPORT_HOSTNAME' => 'false'} }

      it 'does not include host.name' do
        expect(resource_attributes['host.name']).to be_nil
      end
    end

    context 'when hostname reporting is enabled' do
      let(:env_overrides) { {'DD_TRACE_REPORT_HOSTNAME' => 'true'} }

      context 'with DD_HOSTNAME configured' do
        let(:env_overrides) { super().merge('DD_HOSTNAME' => 'custom-host') }

        it 'uses DD_HOSTNAME as host.name' do
          expect(resource_attributes['host.name']).to eq('custom-host')
        end

        context 'and host.name is also configured through tags' do
          let(:env_overrides) { super().merge('DD_HOSTNAME' => 'explicit-host') }
          let(:configuration) do
            proc do |c|
              c.tags = {'host.name' => 'tag-host'}
            end
          end

          it 'prioritizes DD_HOSTNAME over the tagged host.name' do
            expect(resource_attributes['host.name']).to eq('explicit-host')
          end
        end
      end

      context 'with host.name configured through tags' do
        let(:configuration) do
          proc do |c|
            c.tags = {'host.name' => 'tag-host'}
          end
        end

        it 'preserves the tagged host.name' do
          expect(resource_attributes['host.name']).to eq('tag-host')
        end
      end
    end

    context 'with custom Datadog configuration' do
      let(:env_overrides) do
        {
          'DD_SERVICE' => 'unused-name',
          'DD_ENV' => 'unused-env',
          'DD_VERSION' => 'x.y.z',
        }
      end
      let(:configuration) do
        proc do |c|
          c.service = 'test-service'
          c.version = '1.0.0'
          c.env = 'test'
          c.tags = {'team' => 'backend', 'region' => 'us-east-1', 'host.name' => 'myhost'}
          c.tracing.report_hostname = true
        end
      end

      it 'uses configured service metadata and tags as resource attributes' do
        expect(resource_attributes).to include(
          'service.name' => 'test-service',
          'service.version' => '1.0.0',
          'deployment.environment' => 'test',
          'host.name' => 'myhost',
          'team' => 'backend',
          'region' => 'us-east-1',
        )
      end
    end

    context 'without a service configured' do
      it 'applies fallback service name' do
        expect(resource_attributes['service.name']).to eq(Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME)
      end
    end
  end

  describe 'Log Injection' do
    it 'disables Datadog log injection after provider setup' do
      expect(Datadog.configuration.tracing.log_injection).to be(false)
    end
  end

  describe 'Configuration' do
    describe 'default values' do
      it 'uses default HTTP endpoint' do
        expect(exporter_uri).to eq("http://#{agent_host}:4318/v1/logs")
      end

      it 'uses default timeout' do
        expect(exporter_timeout).to eq(10.0)
      end
    end

    describe 'configuration priority' do
      let(:env_overrides) do
        {
          'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://general:4317',
          'OTEL_EXPORTER_OTLP_TIMEOUT' => '8000',
          'OTEL_EXPORTER_OTLP_HEADERS' => 'general=value'
        }
      end
      it 'uses the general OTLP endpoint' do
        expect(exporter_uri).to eq('http://general:4317/v1/logs')
      end

      it 'uses the general OTLP timeout' do
        expect(exporter_timeout).to eq(8.0)
      end

      it 'uses the general OTLP headers' do
        expect(exporter_headers['general']).to eq('value')
      end

      context 'when logs-specific configs are provided' do
        let(:env_overrides) do
          super().merge(
            'DD_LOGS_OTEL_ENABLED' => 'true',
            'OTEL_EXPORTER_OTLP_LOGS_ENDPOINT' => 'http://logs:4318/v1/logs',
            'OTEL_EXPORTER_OTLP_LOGS_TIMEOUT' => '5000',
            'OTEL_EXPORTER_OTLP_LOGS_HEADERS' => 'logs=value',
          )
        end

        it 'uses logs-specific endpoint' do
          expect(exporter_uri).to eq('http://logs:4318/v1/logs')
        end

        it 'uses logs-specific timeout' do
          expect(exporter_timeout).to eq(5.0)
        end

        it 'uses logs-specific headers' do
          expect(exporter_headers['logs']).to eq('value')
        end
      end
    end

    context 'with multiple headers' do
      let(:env_overrides) do
        {
          'OTEL_EXPORTER_OTLP_HEADERS' => 'api-key=secret123,other-config-value=test-value'
        }
      end
      it 'parses all headers correctly' do
        expect(exporter_headers['api-key']).to eq('secret123')
        expect(exporter_headers['other-config-value']).to eq('test-value')
      end
    end

    context 'with malformed logs headers' do
      let(:env_overrides) do
        {
          'OTEL_EXPORTER_OTLP_LOGS_HEADERS' => 'api-key=secret123,malformed'
        }
      end
      it 'returns an empty headers hash' do
        expect(logs_settings.headers).to eq({})
      end
    end

    context 'when logs protocol is set to grpc' do
      let(:env_overrides) { {'OTEL_EXPORTER_OTLP_LOGS_PROTOCOL' => 'grpc'} }
      it 'defaults to HTTP' do
        expect(logs_settings.protocol).to eq('http/protobuf')
        expect(exporter_uri).to eq("http://#{agent_host}:4318/v1/logs")
      end
    end

    context 'when OTEL_LOGS_EXPORTER is none' do
      let(:env_overrides) { {'OTEL_LOGS_EXPORTER' => 'none'} }
      it 'does not add a processor' do
        expect(processor).to be_nil
        expect(Datadog.configuration.tracing.log_injection).to be(true)
      end
    end

    context 'when configuration prevents OTLP logs initialization' do
      let(:env_overrides) { {'OTEL_EXPORTER_OTLP_LOGS_ENDPOINT' => 'not a url'} }
      it 'keeps Datadog log injection enabled' do
        expect(provider).to be_a(::OpenTelemetry::SDK::Logs::LoggerProvider)
        expect(processor).to be_nil
        expect(Datadog.configuration.tracing.log_injection).to be(true)
      end
    end

    context 'when DD_LOGS_OTEL_ENABLED is false' do
      let(:env_overrides) do
        {
          'DD_LOGS_OTEL_ENABLED' => 'false',
          'OTEL_LOGS_EXPORTER' => 'console'
        }
      end
      it 'lets the upstream OpenTelemetry logs SDK configure logs' do
        expect(provider).to be_a(::OpenTelemetry::SDK::Logs::LoggerProvider)
        expect(processor).to be_a(::OpenTelemetry::SDK::Logs::Export::SimpleLogRecordProcessor)
        expect(Datadog.configuration.tracing.log_injection).to be(true)
      end
    end
  end

  describe 'Lifecycle' do
    it 'handles shutdown gracefully' do
      expect { provider.shutdown }.not_to raise_error
      expect { provider.shutdown }.not_to raise_error
    end

    it 'handles force_flush' do
      provider.logger(name: 'app').on_emit(timestamp: Time.now, severity_number: 9, body: 'flush test')
      expect { provider.force_flush }.not_to raise_error
    end
  end
end
