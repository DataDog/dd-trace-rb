# frozen_string_literal: true

require 'spec_helper'

# Tests run under the openfeature appraisal which includes the real OpenFeature SDK
require 'open_feature/sdk'
require 'datadog/open_feature/hooks/flag_eval_hook'

RSpec.describe Datadog::OpenFeature::Hooks::FlagEvalHook do
  subject(:hook) { described_class.new(metrics) }

  let(:metrics) { instance_double(Datadog::OpenFeature::Metrics::FlagEvalMetrics) }

  describe '#finally' do
    let(:hook_context) { instance_double('OpenFeature::SDK::Hooks::HookContext', flag_key: 'test-flag') }

    context 'with successful evaluation' do
      let(:evaluation_details) do
        instance_double(
          'OpenFeature::SDK::EvaluationDetails',
          variant: 'on',
          reason: 'TARGETING_MATCH',
          error_code: nil,
          flag_metadata: {'__dd_allocation_key' => 'my-allocation'}
        )
      end

      it 'calls metrics.record with correct arguments' do
        expect(metrics).to receive(:record).with(
          'test-flag',
          variant: 'on',
          reason: 'TARGETING_MATCH',
          error_code: nil,
          allocation_key: 'my-allocation'
        )

        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
      end
    end

    context 'with error evaluation' do
      let(:evaluation_details) do
        instance_double(
          'OpenFeature::SDK::EvaluationDetails',
          variant: nil,
          reason: 'ERROR',
          error_code: 'FLAG_NOT_FOUND',
          flag_metadata: {}
        )
      end

      it 'passes error_code to metrics.record' do
        expect(metrics).to receive(:record).with(
          'test-flag',
          variant: nil,
          reason: 'ERROR',
          error_code: 'FLAG_NOT_FOUND',
          allocation_key: nil
        )

        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
      end
    end

    context 'without allocation_key in flag_metadata' do
      let(:evaluation_details) do
        instance_double(
          'OpenFeature::SDK::EvaluationDetails',
          variant: 'on',
          reason: 'STATIC',
          error_code: nil,
          flag_metadata: {}
        )
      end

      it 'passes nil for allocation_key' do
        expect(metrics).to receive(:record).with(
          'test-flag',
          variant: 'on',
          reason: 'STATIC',
          error_code: nil,
          allocation_key: nil
        )

        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
      end
    end

    context 'with nil flag_metadata' do
      let(:evaluation_details) do
        instance_double(
          'OpenFeature::SDK::EvaluationDetails',
          variant: 'on',
          reason: 'STATIC',
          error_code: nil,
          flag_metadata: nil
        )
      end

      it 'handles nil flag_metadata gracefully' do
        expect(metrics).to receive(:record).with(
          'test-flag',
          variant: 'on',
          reason: 'STATIC',
          error_code: nil,
          allocation_key: nil
        )

        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
      end
    end

    context 'when metrics is nil' do
      let(:hook) { described_class.new(nil) }
      let(:evaluation_details) do
        instance_double(
          'OpenFeature::SDK::EvaluationDetails',
          variant: 'on',
          reason: 'TARGETING_MATCH',
          error_code: nil,
          flag_metadata: {}
        )
      end

      it 'does nothing without error' do
        expect { hook.finally(hook_context: hook_context, evaluation_details: evaluation_details) }
          .not_to raise_error
      end
    end
  end
end
