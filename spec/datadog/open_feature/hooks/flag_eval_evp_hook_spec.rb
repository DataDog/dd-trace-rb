# frozen_string_literal: true

require 'spec_helper'

# Tests run under the openfeature appraisal which includes the real OpenFeature SDK
require 'open_feature/sdk'
require 'datadog/open_feature/hooks/flag_eval_evp_hook'
require 'datadog/open_feature/flagevaluation/writer'

RSpec.describe Datadog::OpenFeature::Hooks::FlagEvalEVPHook do
  subject(:hook) { described_class.new(writer) }

  let(:writer) { instance_double(Datadog::OpenFeature::FlagEvaluation::Writer, enqueue: nil) }

  let(:eval_context) { ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'user-7', env: 'prod') }
  let(:hook_context) { double('HookContext', flag_key: 'my-flag', evaluation_context: eval_context) }

  def build_evaluation_details(variant:, error_message: nil, error_code: nil, flag_metadata: {})
    instance_double(
      'OpenFeature::SDK::EvaluationDetails',
      variant: variant,
      error_message: error_message,
      error_code: error_code,
      flag_metadata: flag_metadata,
    )
  end

  describe '#finally — captures cheaply and enqueues (async boundary)' do
    let(:evaluation_details) do
      build_evaluation_details(
        variant: 'on',
        flag_metadata: {'__dd_allocation_key' => 'alloc-9', 'dd.eval.timestamp_ms' => 1_700_000_000_000},
      )
    end

    # Variant comes from evaluation_details.variant (the OpenFeature variant), NEVER the value.
    # The hook is never given the evaluated value, so it cannot accidentally emit it.
    it 'enqueues the variant from evaluation_details.variant' do
      expect(writer).to receive(:enqueue).with(hash_including(variant: 'on'))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it 'enqueues runtime_default false for a successful variant result' do
      expect(writer).to receive(:enqueue).with(hash_including(runtime_default: false))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    # allocation_key read from metadata['__dd_allocation_key'] — the SAME source the OTel hook uses.
    it 'enqueues allocation_key from the same metadata key the OTel hook reads' do
      expect(writer).to receive(:enqueue).with(hash_including(allocation_key: 'alloc-9'))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    # eval-time read from the provider-stamped 'dd.eval.timestamp_ms' metadata key.
    it 'enqueues eval_time_ms from the provider-stamped dd.eval.timestamp_ms metadata' do
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_700_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it 'enqueues flag_key, targeting_key and attrs without reason' do
      expect(writer).to receive(:enqueue) do |event|
        expect(event).to include(
          flag_key: 'my-flag',
          targeting_key: 'user-7',
          attrs: {'env' => 'prod'},
        )
        expect(event).not_to have_key(:reason)
      end
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it 'also accepts duck-typed contexts that expose attributes' do
      ctx = Struct.new(:targeting_key, :attributes).new('user-9', {'tier' => 'gold'})
      hook_ctx = double('HookContext', flag_key: 'my-flag', evaluation_context: ctx)

      expect(writer).to receive(:enqueue).with(hash_including(targeting_key: 'user-9', attrs: {'tier' => 'gold'}))
      hook.finally(hook_context: hook_ctx, evaluation_details: evaluation_details)
    end

    it 'enqueues error_message when present' do
      details = build_evaluation_details(variant: nil, error_message: 'flag not found')
      expect(writer).to receive(:enqueue).with(hash_including(error_message: 'flag not found'))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it 'does NOT touch the aggregator on the hook path (only enqueues — async boundary)' do
      # The hook collaborates ONLY with writer#enqueue; it has no aggregator reference at all.
      expect(hook.instance_variables).not_to include(:@aggregator)
      expect(writer).to receive(:enqueue).once
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end
  end

  describe '#finally — runtime-default + missing-metadata edge cases' do
    # Fallback: when the provider did not stamp a timestamp, fall back to hook-fire time.
    it 'falls back to a real hook-fire timestamp when dd.eval.timestamp_ms is absent' do
      details = build_evaluation_details(variant: 'on')
      Datadog::Core::Utils::Time.now_provider = -> { ::Time.at(1_650_000_000) }
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_650_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    ensure
      Datadog::Core::Utils::Time.now_provider = -> { ::Time.now }
    end

    # Concern: detect runtime default from ABSENT variant, passed through as nil (aggregator decides).
    it 'passes a nil variant through unchanged (runtime-default signal preserved)' do
      details = build_evaluation_details(variant: nil)
      expect(writer).to receive(:enqueue).with(hash_including(variant: nil, runtime_default: true))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it 'marks type mismatch as runtime default even when the SDK exposes a variant' do
      details = build_evaluation_details(variant: 'variant-a', error_code: 'TYPE_MISMATCH')
      expect(writer).to receive(:enqueue).with(hash_including(variant: 'variant-a', runtime_default: true))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it 'handles a nil evaluation_context without raising' do
      details = build_evaluation_details(variant: 'v')
      ctx = double('HookContext', flag_key: 'f', evaluation_context: nil)
      expect(writer).to receive(:enqueue).with(hash_including(targeting_key: nil, attrs: {}))
      expect { hook.finally(hook_context: ctx, evaluation_details: details) }.not_to raise_error
    end
  end
end
