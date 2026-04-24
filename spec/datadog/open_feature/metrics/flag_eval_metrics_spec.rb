# frozen_string_literal: true

require 'spec_helper'

# Tests run under the openfeature appraisal which includes the real OTel SDK
require 'opentelemetry-metrics-sdk'
require 'datadog/open_feature/metrics/flag_eval_metrics'

RSpec.describe Datadog::OpenFeature::Metrics::FlagEvalMetrics do
  subject(:metrics) { described_class.new(telemetry: telemetry, logger: logger) }

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { logger_allowing_debug }

  # Mock configuration for OTel metrics enabled setting
  let(:otel_metrics_settings) { instance_double('OtelMetricsSettings', enabled: true) }
  let(:otel_settings) { instance_double('OtelSettings', metrics: otel_metrics_settings) }
  let(:configuration) { instance_double('Configuration', opentelemetry: otel_settings) }

  before do
    # Stub Datadog.configuration for OTel metrics enabled check
    allow(Datadog).to receive(:configuration).and_return(configuration)
  end

  describe '#record' do
    context 'when DD_METRICS_OTEL_ENABLED is false' do
      let(:otel_metrics_settings) { instance_double('OtelMetricsSettings', enabled: false) }

      it 'does nothing without error' do
        expect do
          metrics.record(
            'test_flag',
            variant: 'control',
            reason: 'TARGETING_MATCH',
            allocation_key: 'rollout-1'
          )
        end.not_to raise_error
      end

      it 'logs debug message about metrics being disabled' do
        expect_lazy_log(logger, :debug, /OTel metrics not enabled/)

        metrics.record(
          'test_flag',
          variant: 'control',
          reason: 'TARGETING_MATCH'
        )
      end
    end

    context 'when OTel metrics SDK is not available' do
      before do
        allow(OpenTelemetry).to receive(:meter_provider).and_return(nil)
        # Stub the initialization attempt - it will fail to load the SDK
        allow(metrics).to receive(:require).with('opentelemetry-metrics-sdk').and_raise(LoadError)
      end

      it 'does nothing without error' do
        expect do
          metrics.record(
            'test_flag',
            variant: 'control',
            reason: 'TARGETING_MATCH',
            allocation_key: 'rollout-1'
          )
        end.not_to raise_error
      end
    end

    context 'when meter provider needs direct initialization' do
      let(:meter_provider_class) { Class.new }
      let(:meter_provider) { instance_double('MeterProvider') }
      let(:meter) { instance_double('Meter') }
      let(:counter) { instance_double('Counter') }
      let(:components) { instance_double('Components') }
      let(:otel_metrics_class) do
        Class.new do
          def self.initialize!(_components)
            true
          end
        end
      end

      before do
        stub_const('OpenTelemetry::SDK::Metrics::MeterProvider', meter_provider_class)
        stub_const('Datadog::OpenTelemetry::Metrics', otel_metrics_class)
        # First call returns nil (not initialized), second call returns the provider
        call_count = 0
        allow(OpenTelemetry).to receive(:meter_provider) do
          call_count += 1
          (call_count == 1) ? nil : meter_provider
        end
        allow(meter_provider).to receive(:is_a?).and_return(false)
        allow(meter_provider).to receive(:is_a?).with(meter_provider_class).and_return(true)
        allow(meter_provider).to receive(:meter).with('ddtrace.openfeature').and_return(meter)
        allow(meter).to receive(:create_counter).and_return(counter)

        # Mock direct initialization - stub require to succeed
        allow(metrics).to receive(:require).with('opentelemetry-metrics-sdk').and_return(true)
        allow(metrics).to receive(:require).with('datadog/opentelemetry/metrics').and_return(true)
        allow(Datadog).to receive(:send).with(:components).and_return(components)
        allow(otel_metrics_class).to receive(:initialize!).with(components).and_return(true)
      end

      it 'initializes the meter provider directly and records metrics' do
        expect(Datadog::OpenTelemetry::Metrics).to receive(:initialize!).with(components)
        expect(counter).to receive(:add).with(1, attributes: hash_including('feature_flag.key' => 'my_flag'))

        metrics.record('my_flag', variant: 'on', reason: 'TARGETING_MATCH')
      end

      it 'logs debug message about direct initialization' do
        allow(counter).to receive(:add)
        expect_lazy_log(logger, :debug, /Initializing OTel meter provider directly/)

        metrics.record('my_flag', variant: 'on', reason: 'TARGETING_MATCH')
      end
    end

    context 'when OTel SDK MeterProvider is available' do
      let(:meter_provider_class) { Class.new }
      let(:meter_provider) { instance_double('MeterProvider') }
      let(:meter) { instance_double('Meter') }
      let(:counter) { instance_double('Counter') }

      before do
        stub_const('OpenTelemetry::SDK::Metrics::MeterProvider', meter_provider_class)
        allow(OpenTelemetry).to receive(:meter_provider).and_return(meter_provider)
        allow(meter_provider).to receive(:is_a?).and_return(false)
        allow(meter_provider).to receive(:is_a?)
          .with(meter_provider_class).and_return(true)
        allow(meter_provider).to receive(:meter)
          .with('ddtrace.openfeature').and_return(meter)
        allow(meter).to receive(:create_counter).and_return(counter)
      end

      context 'with successful evaluation (targeting_match)' do
        it 'records metric with correct attributes including allocation_key' do
          expect(counter).to receive(:add).with(
            1,
            attributes: {
              'feature_flag.key' => 'my_flag',
              'feature_flag.result.variant' => 'treatment',
              'feature_flag.result.reason' => 'targeting_match',
              'feature_flag.result.allocation_key' => 'rollout-1',
            }
          )

          metrics.record(
            'my_flag',
            variant: 'treatment',
            reason: 'TARGETING_MATCH',
            allocation_key: 'rollout-1'
          )
        end
      end

      context 'with static reason' do
        it 'records metric with reason=static' do
          expect(counter).to receive(:add).with(
            1,
            attributes: hash_including('feature_flag.result.reason' => 'static')
          )

          metrics.record(
            'flag',
            variant: 'on',
            reason: 'STATIC',
            allocation_key: 'default-allocation'
          )
        end
      end

      context 'with split reason' do
        it 'records metric with reason=split and includes allocation_key' do
          expect(counter).to receive(:add).with(
            1,
            attributes: hash_including(
              'feature_flag.result.reason' => 'split',
              'feature_flag.result.allocation_key' => 'split-allocation'
            )
          )

          metrics.record(
            'flag',
            variant: 'on',
            reason: 'SPLIT',
            allocation_key: 'split-allocation'
          )
        end
      end

      context 'with error evaluation (FLAG_NOT_FOUND)' do
        it 'records metric with error.type attribute and no allocation_key' do
          expect(counter).to receive(:add).with(
            1,
            attributes: {
              'feature_flag.key' => 'missing_flag',
              'feature_flag.result.variant' => '',
              'feature_flag.result.reason' => 'error',
              'error.type' => 'flag_not_found',
            }
          )

          metrics.record(
            'missing_flag',
            variant: nil,
            reason: 'ERROR',
            error_code: 'FLAG_NOT_FOUND'
          )
        end
      end

      context 'with TYPE_MISMATCH error' do
        it 'maps error code to type_mismatch' do
          expect(counter).to receive(:add).with(
            1,
            attributes: hash_including('error.type' => 'type_mismatch')
          )

          metrics.record(
            'flag',
            variant: nil,
            reason: 'ERROR',
            error_code: 'TYPE_MISMATCH'
          )
        end
      end

      context 'with PARSE_ERROR' do
        it 'maps error code to parse_error' do
          expect(counter).to receive(:add).with(
            1,
            attributes: hash_including('error.type' => 'parse_error')
          )

          metrics.record(
            'flag',
            variant: nil,
            reason: 'ERROR',
            error_code: 'PARSE_ERROR'
          )
        end
      end

      context 'with PROVIDER_NOT_READY error' do
        it 'maps error code to provider_not_ready' do
          expect(counter).to receive(:add).with(
            1,
            attributes: hash_including('error.type' => 'provider_not_ready')
          )

          metrics.record(
            'flag',
            variant: nil,
            reason: 'ERROR',
            error_code: 'PROVIDER_NOT_READY'
          )
        end
      end

      context 'with disabled flag' do
        it 'does not include allocation_key for disabled reason' do
          expect(counter).to receive(:add).with(
            1,
            attributes: {
              'feature_flag.key' => 'disabled_flag',
              'feature_flag.result.variant' => '',
              'feature_flag.result.reason' => 'disabled',
            }
          )

          metrics.record(
            'disabled_flag',
            variant: nil,
            reason: 'DISABLED',
            allocation_key: 'should-not-appear'
          )
        end
      end

      context 'with default reason' do
        it 'does not include allocation_key for default reason' do
          expect(counter).to receive(:add).with(
            1,
            attributes: {
              'feature_flag.key' => 'flag',
              'feature_flag.result.variant' => '',
              'feature_flag.result.reason' => 'default',
            }
          )

          metrics.record(
            'flag',
            variant: nil,
            reason: 'DEFAULT',
            allocation_key: 'should-not-appear'
          )
        end
      end

      context 'with nil variant' do
        it 'uses empty string for variant' do
          expect(counter).to receive(:add).with(
            1,
            attributes: hash_including('feature_flag.result.variant' => '')
          )

          metrics.record(
            'flag',
            variant: nil,
            reason: 'TARGETING_MATCH'
          )
        end
      end

      context 'with empty allocation_key' do
        it 'does not include allocation_key when empty' do
          expect(counter).to receive(:add) do |value, attributes:|
            expect(attributes).not_to have_key('feature_flag.result.allocation_key')
          end

          metrics.record(
            'flag',
            variant: 'on',
            reason: 'TARGETING_MATCH',
            allocation_key: ''
          )
        end
      end

      context 'when counter.add raises an error' do
        before do
          allow(counter).to receive(:add).and_raise(StandardError.new('OTel error'))
          allow(telemetry).to receive(:report)
        end

        it 'catches the error and reports via telemetry' do
          expect(telemetry).to receive(:report).with(
            kind_of(StandardError),
            description: 'OpenFeature: Failed to record evaluation metric'
          )
          expect_lazy_log(logger, :debug, /Failed to record evaluation metric/)

          # Should not raise
          expect do
            metrics.record(
              'flag',
              variant: 'on',
              reason: 'TARGETING_MATCH'
            )
          end.not_to raise_error
        end
      end
    end
  end

  describe 'error code mapping' do
    it 'maps FLAG_NOT_FOUND to flag_not_found' do
      expect(described_class::ERROR_TYPE_MAP['FLAG_NOT_FOUND']).to eq('flag_not_found')
    end

    it 'maps TYPE_MISMATCH to type_mismatch' do
      expect(described_class::ERROR_TYPE_MAP['TYPE_MISMATCH']).to eq('type_mismatch')
    end

    it 'maps PARSE_ERROR to parse_error' do
      expect(described_class::ERROR_TYPE_MAP['PARSE_ERROR']).to eq('parse_error')
    end

    it 'maps PROVIDER_NOT_READY to provider_not_ready' do
      expect(described_class::ERROR_TYPE_MAP['PROVIDER_NOT_READY']).to eq('provider_not_ready')
    end

    it 'maps GENERAL to general' do
      expect(described_class::ERROR_TYPE_MAP['GENERAL']).to eq('general')
    end

    it 'maps PROVIDER_FATAL to general' do
      expect(described_class::ERROR_TYPE_MAP['PROVIDER_FATAL']).to eq('general')
    end

    it 'maps UNKNOWN_TYPE to general' do
      expect(described_class::ERROR_TYPE_MAP['UNKNOWN_TYPE']).to eq('general')
    end
  end

  describe 'reason mapping' do
    it 'maps TARGETING_MATCH to targeting_match' do
      expect(described_class::REASON_MAP['TARGETING_MATCH']).to eq('targeting_match')
    end

    it 'maps ERROR to error' do
      expect(described_class::REASON_MAP['ERROR']).to eq('error')
    end

    it 'maps DEFAULT to default' do
      expect(described_class::REASON_MAP['DEFAULT']).to eq('default')
    end

    it 'maps DISABLED to disabled' do
      expect(described_class::REASON_MAP['DISABLED']).to eq('disabled')
    end

    it 'maps SPLIT to split' do
      expect(described_class::REASON_MAP['SPLIT']).to eq('split')
    end

    it 'maps STATIC to static' do
      expect(described_class::REASON_MAP['STATIC']).to eq('static')
    end

    it 'maps UNKNOWN to unknown' do
      expect(described_class::REASON_MAP['UNKNOWN']).to eq('unknown')
    end
  end
end
