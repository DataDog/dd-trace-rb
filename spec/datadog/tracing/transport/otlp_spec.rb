# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/configuration/settings'
require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/transport/otlp'

RSpec.describe Datadog::Tracing::Transport::OTLP do
  let(:logger) { logger_allowing_debug }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  describe '.resolve_endpoint' do
    subject(:endpoint) { described_class.resolve_endpoint(settings.tracing.otlp, agent_settings) }

    context 'when OTEL_EXPORTER_OTLP_TRACES_ENDPOINT is set' do
      before { settings.tracing.otlp.endpoint = 'http://collector:4318/custom/path' }

      it 'uses the traces endpoint as-is' do
        is_expected.to eq('http://collector:4318/custom/path')
      end

      context 'and OTEL_EXPORTER_OTLP_ENDPOINT is also set' do
        before { settings.tracing.otlp.endpoint_fallback = 'http://fallback:4318' }

        it 'prefers the traces endpoint' do
          is_expected.to eq('http://collector:4318/custom/path')
        end
      end
    end

    context 'when only OTEL_EXPORTER_OTLP_ENDPOINT is set' do
      before { settings.tracing.otlp.endpoint_fallback = 'http://fallback:4318' }

      it 'appends /v1/traces' do
        is_expected.to eq('http://fallback:4318/v1/traces')
      end

      context 'with a trailing slash' do
        before { settings.tracing.otlp.endpoint_fallback = 'http://fallback:4318/' }

        it 'strips the trailing slash before appending /v1/traces' do
          is_expected.to eq('http://fallback:4318/v1/traces')
        end
      end
    end

    context 'when no endpoint is configured' do
      it 'computes the default from the agent host on port 4318' do
        is_expected.to eq("http://#{agent_settings.hostname}:4318/v1/traces")
      end
    end
  end

  describe '.resource_attributes' do
    subject(:attributes) { described_class.resource_attributes(settings) }

    before do
      settings.service = 'svc'
      settings.env = 'prod'
      settings.version = '1.2.3'
    end

    def value_for(key)
      attributes.find { |a| a[:key] == key }&.dig(:value, :stringValue)
    end

    it 'maps DD_SERVICE/DD_ENV/DD_VERSION to OTLP resource attributes' do
      expect(value_for('service.name')).to eq('svc')
      expect(value_for('deployment.environment.name')).to eq('prod')
      expect(value_for('service.version')).to eq('1.2.3')
    end

    it 'sets the telemetry SDK attributes' do
      expect(value_for('telemetry.sdk.name')).to eq('datadog')
      expect(value_for('telemetry.sdk.language')).to eq('ruby')
      expect(value_for('telemetry.sdk.version')).to eq(Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION)
    end

    it 'includes runtime-id for parity with libdatadog languages' do
      expect(value_for('runtime-id')).to eq(Datadog::Core::Environment::Identity.id)
    end
  end

  describe '.build' do
    subject(:transport) { described_class.build(settings: settings, agent_settings: agent_settings, logger: logger) }

    before do
      settings.tracing.otlp.endpoint = 'https://collector:4318/v1/traces'
      settings.tracing.otlp.headers = {'api-key' => 'secret'}
      settings.tracing.otlp.timeout_millis = 5000
    end

    it 'builds a Transport with an exporter configured from settings' do
      expect(transport).to be_a(described_class::Transport)
      expect(transport.exporter.uri.to_s).to eq('https://collector:4318/v1/traces')
      expect(transport.exporter.headers).to eq('api-key' => 'secret')
      expect(transport.exporter.timeout_seconds).to eq(5.0)
    end

    context 'header and timeout fallbacks' do
      before do
        settings.tracing.otlp.headers = nil
        settings.tracing.otlp.headers_fallback = {'fallback-key' => 'v'}
        settings.tracing.otlp.timeout_millis = nil
        settings.tracing.otlp.timeout_millis_fallback = 7000
      end

      it 'falls back to the general headers and timeout' do
        expect(transport.exporter.headers).to eq('fallback-key' => 'v')
        expect(transport.exporter.timeout_seconds).to eq(7.0)
      end
    end
  end

  describe described_class::Transport do
    subject(:transport) { described_class.new(exporter: exporter, encoder: encoder, logger: logger) }

    let(:exporter) { instance_double(Datadog::Tracing::Transport::OTLP::Exporter) }
    let(:encoder) { instance_double(Datadog::Tracing::Transport::OTLP::Encoder) }

    def build_trace(sampling_priority:)
      span = Datadog::Tracing::Span.new('op', service: 'svc', resource: 'op', id: 1, trace_id: 2)
      span.start_time = Time.at(1_700_000_000, 0)
      span.duration = 0.0
      Datadog::Tracing::TraceSegment.new([span], id: 2, root_span_id: 1, sampling_priority: sampling_priority)
    end

    describe '#send_traces' do
      context 'with a sampled trace (priority >= AUTO_KEEP)' do
        let(:trace) { build_trace(sampling_priority: 1) }

        before do
          allow(encoder).to receive(:encode).and_return('{"resourceSpans":[]}')
          allow(exporter).to receive(:export).and_return(true)
        end

        it 'encodes and exports the trace' do
          responses = transport.send_traces([trace])

          expect(encoder).to have_received(:encode).with(trace)
          expect(exporter).to have_received(:export).with('{"resourceSpans":[]}')
          expect(responses.length).to eq(1)
          expect(responses.first.trace_count).to eq(1)
          expect(responses.first.ok?).to be(true)
        end

        context 'when the export fails' do
          before { allow(exporter).to receive(:export).and_return(false) }

          it 'reports a server error' do
            response = transport.send_traces([trace]).first
            expect(response.server_error?).to be(true)
            expect(response.ok?).to be(false)
          end
        end
      end

      context 'with an unsampled trace (priority < AUTO_KEEP)' do
        let(:trace) { build_trace(sampling_priority: 0) }

        it 'drops the trace without encoding or exporting' do
          expect(encoder).not_to receive(:encode)
          expect(exporter).not_to receive(:export)

          response = transport.send_traces([trace]).first
          expect(response.trace_count).to eq(0)
        end
      end

      context 'with a user-rejected trace (priority -1)' do
        let(:trace) { build_trace(sampling_priority: -1) }

        it 'drops the trace' do
          expect(exporter).not_to receive(:export)
          transport.send_traces([trace])
        end
      end
    end
  end
end
