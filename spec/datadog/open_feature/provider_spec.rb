# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/provider'
require 'datadog/open_feature/evaluation_engine'

RSpec.describe Datadog::OpenFeature::Provider do
  before do
    allow(telemetry).to receive(:report)
    allow(reporter).to receive(:report)
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
  end

  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(reporter, telemetry: telemetry, logger: logger) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { instance_double(Datadog::Core::Logger) }

  subject(:provider) { described_class.new }

  describe '#fetch_boolean_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_boolean_value(flag_key: 'flag', default_value: false)

        expect(result.value).to eq(false)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_string_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_string_value(flag_key: 'flag', default_value: 'default')

        expect(result.value).to eq('default')
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_number_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_number_value(flag_key: 'flag', default_value: 0)

        expect(result.value).to eq(0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_integer_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_integer_value(flag_key: 'flag', default_value: 1)

        expect(result.value).to eq(1)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_float_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_float_value(flag_key: 'flag', default_value: 0.0)

        expect(result.value).to eq(0.0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_object_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_object_value(flag_key: 'flag', default_value: {'default' => true})

        expect(result.value).to eq({'default' => true})
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when value is a JSON string' do
      before do
        allow(engine).to receive(:fetch_value).and_return(details)
        allow(details).to receive(:value).and_raise(Datadog::Core::FeatureFlags::Error, 'Ooops')
      end

      let(:details) do
        Datadog::OpenFeature::ResolutionDetails.new(
          value: '{}', reason: 'MATCH', variant: 'blue', flag_metadata: {},
          allocation_key: 'joe', extra_logging: {}, log?: true, error?: false
        )
      end

      it 'returns error and fallback to the default value' do
        result = provider.fetch_object_value(flag_key: 'flag', default_value: {'default' => true})

        expect(result.value).to eq('default' => true)
        expect(result.reason).to eq('ERROR')
      end
    end
  end
end
