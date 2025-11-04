# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::OpenTelemetry::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe '#opentelemetry' do
    describe '#exporter' do
      describe '#protocol' do
        subject(:protocol) { settings.opentelemetry.exporter.protocol }

        context 'when OTEL_EXPORTER_OTLP_PROTOCOL' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_PROTOCOL' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq('grpc') }
          end

          context 'is defined' do
            let(:env_value) { 'http/protobuf' }

            it { is_expected.to eq('http/protobuf') }
          end
        end
      end

      describe '#timeout' do
        subject(:timeout) { settings.opentelemetry.exporter.timeout }

        context 'when OTEL_EXPORTER_OTLP_TIMEOUT' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_TIMEOUT' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq(10_000) }
          end

          context 'is defined' do
            let(:env_value) { '5000' }

            it { is_expected.to eq(5_000) }
          end
        end
      end

      describe '#headers' do
        subject(:headers) { settings.opentelemetry.exporter.headers }

        context 'when OTEL_EXPORTER_OTLP_HEADERS' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_HEADERS' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq({}) }
          end

          context 'is valid JSON' do
            let(:env_value) { '{"key1":"value1","key2":"value2"}' }

            it { is_expected.to eq('key1' => 'value1', 'key2' => 'value2') }
          end

          context 'is invalid JSON' do
            let(:env_value) { 'invalid json' }

            it { is_expected.to eq({}) }
          end
        end
      end

      describe '#endpoint' do
        subject(:endpoint) { settings.opentelemetry.exporter.endpoint }

        context 'when OTEL_EXPORTER_OTLP_ENDPOINT' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_ENDPOINT' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq("http://127.0.0.1:4317") }

            context 'with http/protobuf protocol' do
              around do |example|
                ClimateControl.modify('OTEL_EXPORTER_OTLP_PROTOCOL' => 'http/protobuf') do
                  example.run
                end
              end

              it { is_expected.to eq("http://127.0.0.1:4318") }
            end

            context 'with DD_TRACE_AGENT_URL set' do
              around do |example|
                ClimateControl.modify('DD_TRACE_AGENT_URL' => 'http://custom-host:8126') do
                  example.run
                end
              end

              it { is_expected.to eq("http://custom-host:4317") }
            end

            context 'with DD_AGENT_HOST set' do
              around do |example|
                ClimateControl.modify('DD_AGENT_HOST' => 'custom-host') do
                  example.run
                end
              end

              it { is_expected.to eq("http://custom-host:4317") }
            end
          end

          context 'is defined' do
            let(:env_value) { 'http://localhost:4317' }

            it { is_expected.to eq('http://localhost:4317') }
          end
        end
      end
    end

    describe '#metrics' do
      describe '#enabled' do
        subject(:enabled) { settings.opentelemetry.metrics.enabled }

        context 'when DD_METRICS_OTEL_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_METRICS_OTEL_ENABLED' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to be false }
          end

          context 'is true' do
            let(:env_value) { 'true' }

            it { is_expected.to be true }
          end

          context 'is false' do
            let(:env_value) { 'false' }

            it { is_expected.to be false }
          end
        end
      end

      describe '#exporter' do
        subject(:exporter) { settings.opentelemetry.metrics.exporter }

        context 'when OTEL_METRICS_EXPORTER' do
          around do |example|
            ClimateControl.modify('OTEL_METRICS_EXPORTER' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq('otlp') }
          end

          context 'is defined' do
            let(:env_value) { 'prometheus' }

            it { is_expected.to eq('prometheus') }
          end
        end
      end

      describe '#export_interval' do
        subject(:export_interval) { settings.opentelemetry.metrics.export_interval }

        context 'when OTEL_METRIC_EXPORT_INTERVAL' do
          around do |example|
            ClimateControl.modify('OTEL_METRIC_EXPORT_INTERVAL' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq(60_000) }
          end

          context 'is defined' do
            let(:env_value) { '30000' }

            it { is_expected.to eq(30_000) }
          end
        end
      end

      describe '#export_timeout' do
        subject(:export_timeout) { settings.opentelemetry.metrics.export_timeout }

        context 'when OTEL_METRIC_EXPORT_TIMEOUT' do
          around do |example|
            ClimateControl.modify('OTEL_METRIC_EXPORT_TIMEOUT' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq(30_000) }
          end

          context 'is defined' do
            let(:env_value) { '15000' }

            it { is_expected.to eq(15_000) }
          end
        end
      end

      describe '#temporality_preference' do
        subject(:temporality_preference) { settings.opentelemetry.metrics.temporality_preference }

        context 'when OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE' => env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:env_value) { nil }

            it { is_expected.to eq('delta') }
          end

          context 'is defined' do
            let(:env_value) { 'cumulative' }

            it { is_expected.to eq('cumulative') }
          end
        end
      end

      describe '#endpoint' do
        subject(:endpoint) { settings.opentelemetry.metrics.endpoint }

        context 'when OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_METRICS_ENDPOINT' => metrics_env_value, 'OTEL_EXPORTER_OTLP_ENDPOINT' => general_env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:metrics_env_value) { nil }

            context 'and OTEL_EXPORTER_OTLP_ENDPOINT is not defined' do
              let(:general_env_value) { nil }

              it { is_expected.to be_nil }

              context 'with http/protobuf protocol' do
                around do |example|
                  ClimateControl.modify('OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'http/protobuf') do
                    example.run
                  end
                end

                it { is_expected.to eq("http://127.0.0.1:4318/v1/metrics") }
              end

              context 'with DD_TRACE_AGENT_URL set and http/protobuf protocol' do
                around do |example|
                  ClimateControl.modify(
                    'DD_TRACE_AGENT_URL' => 'http://custom-host:8126',
                    'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'http/protobuf'
                  ) do
                    example.run
                  end
                end

                it { is_expected.to eq("http://custom-host:4318/v1/metrics") }
              end

              context 'with DD_AGENT_HOST set and http/protobuf protocol' do
                around do |example|
                  ClimateControl.modify(
                    'DD_AGENT_HOST' => 'custom-host',
                    'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => 'http/protobuf'
                  ) do
                    example.run
                  end
                end

                it { is_expected.to eq("http://custom-host:4318/v1/metrics") }
              end
            end

            context 'and OTEL_EXPORTER_OTLP_ENDPOINT is defined' do
              let(:general_env_value) { 'http://localhost:4318' }

              it { is_expected.to be_nil }
            end
          end

          context 'is defined' do
            let(:metrics_env_value) { 'http://localhost:4317' }
            let(:general_env_value) { nil }

            it { is_expected.to eq('http://localhost:4317') }
          end
        end
      end

      describe '#headers' do
        subject(:headers) { settings.opentelemetry.metrics.headers }

        context 'when OTEL_EXPORTER_OTLP_METRICS_HEADERS' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_METRICS_HEADERS' => metrics_env_value, 'OTEL_EXPORTER_OTLP_HEADERS' => general_env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:metrics_env_value) { nil }

            context 'and OTEL_EXPORTER_OTLP_HEADERS is not defined' do
              let(:general_env_value) { nil }

              it { is_expected.to eq({}) }
            end

            context 'and OTEL_EXPORTER_OTLP_HEADERS is valid JSON' do
              let(:general_env_value) { '{"key1":"value1"}' }

              it { is_expected.to eq('key1' => 'value1') }
            end
          end

          context 'is valid JSON' do
            let(:metrics_env_value) { '{"key1":"value1","key2":"value2"}' }
            let(:general_env_value) { nil }

            it { is_expected.to eq('key1' => 'value1', 'key2' => 'value2') }
          end

          context 'is invalid JSON' do
            let(:metrics_env_value) { 'invalid json' }
            let(:general_env_value) { nil }

            it { is_expected.to eq({}) }
          end
        end
      end

      describe '#timeout' do
        subject(:timeout) { settings.opentelemetry.metrics.timeout }

        context 'when OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_METRICS_TIMEOUT' => metrics_env_value, 'OTEL_EXPORTER_OTLP_TIMEOUT' => general_env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:metrics_env_value) { nil }

            context 'and OTEL_EXPORTER_OTLP_TIMEOUT is not defined' do
              let(:general_env_value) { nil }

              it { is_expected.to eq(10_000) }
            end

            context 'and OTEL_EXPORTER_OTLP_TIMEOUT is defined' do
              let(:general_env_value) { '8000' }

              it { is_expected.to eq(8_000) }
            end
          end

          context 'is defined' do
            let(:metrics_env_value) { '5000' }
            let(:general_env_value) { nil }

            it { is_expected.to eq(5_000) }
          end
        end
      end

      describe '#protocol' do
        subject(:protocol) { settings.opentelemetry.metrics.protocol }

        context 'when OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' do
          around do |example|
            ClimateControl.modify('OTEL_EXPORTER_OTLP_METRICS_PROTOCOL' => metrics_env_value, 'OTEL_EXPORTER_OTLP_PROTOCOL' => general_env_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:metrics_env_value) { nil }

            context 'and OTEL_EXPORTER_OTLP_PROTOCOL is not defined' do
              let(:general_env_value) { nil }

              it { is_expected.to eq('grpc') }
            end

            context 'and OTEL_EXPORTER_OTLP_PROTOCOL is defined' do
              let(:general_env_value) { 'http/protobuf' }

              it { is_expected.to eq('http/protobuf') }
            end
          end

          context 'is defined' do
            let(:metrics_env_value) { 'http/protobuf' }
            let(:general_env_value) { nil }

            it { is_expected.to eq('http/protobuf') }
          end
        end
      end
    end
  end
end

