# frozen_string_literal: true

require 'spec_helper'

# Tests run under the openfeature appraisal which includes the real OpenFeature SDK
require 'open_feature/sdk'
require 'datadog/open_feature/hooks/flag_eval_evp_hook'
require 'datadog/open_feature/flagevaluation/writer'

RSpec.describe Datadog::OpenFeature::Hooks::FlagEvalEVPHook do
  subject(:hook) { described_class.new(writer) }

  let(:writer) { instance_double(Datadog::OpenFeature::FlagEvaluation::Writer, enqueue: nil) }

  # The hook receives a duck-typed context exposing #targeting_key + #attributes (the provider adapts
  # the real EvaluationContext into Provider::EvpEvalContext, which is exactly this shape).
  let(:eval_context) { double('EvpEvalContext', targeting_key: 'user-7', attributes: {'env' => 'prod'}) }
  let(:hook_context) { double('HookContext', flag_key: 'my-flag', evaluation_context: eval_context) }

  describe '#finally — captures cheaply and enqueues (G2 async boundary)' do
    let(:evaluation_details) do
      instance_double(
        'OpenFeature::SDK::EvaluationDetails',
        variant: 'on',
        reason: 'TARGETING_MATCH',
        flag_metadata: {'__dd_allocation_key' => 'alloc-9', 'dd.eval.timestamp_ms' => 1_700_000_000_000},
      )
    end

    # G1: variant comes from evaluation_details.variant (the OpenFeature variant), NEVER the value.
    # The hook is never given the evaluated value, so it cannot accidentally emit it.
    it 'enqueues the variant from evaluation_details.variant' do
      expect(writer).to receive(:enqueue).with(hash_including(variant: 'on'))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    # G7: allocation_key read from metadata['__dd_allocation_key'] — the SAME source the OTel hook uses.
    it 'enqueues allocation_key from the same metadata key the OTel hook reads' do
      expect(writer).to receive(:enqueue).with(hash_including(allocation_key: 'alloc-9'))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    # G13: eval-time read from the provider-stamped 'dd.eval.timestamp_ms' metadata key.
    it 'enqueues eval_time_ms from the provider-stamped dd.eval.timestamp_ms metadata' do
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_700_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it 'enqueues flag_key, reason, targeting_key and attrs' do
      expect(writer).to receive(:enqueue).with(
        hash_including(
          flag_key: 'my-flag',
          reason: 'TARGETING_MATCH',
          targeting_key: 'user-7',
          attrs: {'env' => 'prod'},
        )
      )
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it 'does NOT touch the aggregator on the hook path (only enqueues — async boundary)' do
      # The hook collaborates ONLY with writer#enqueue; it has no aggregator reference at all.
      expect(hook.instance_variables).not_to include(:@aggregator)
      expect(writer).to receive(:enqueue).once
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end
  end

  describe '#finally — runtime-default + missing-metadata edge cases' do
    # G13 fallback: when the provider did not stamp a timestamp, fall back to hook-fire time.
    it 'falls back to a real hook-fire timestamp when dd.eval.timestamp_ms is absent' do
      details = instance_double(
        'OpenFeature::SDK::EvaluationDetails',
        variant: 'on', reason: 'STATIC', flag_metadata: {},
      )
      Datadog::Core::Utils::Time.now_provider = -> { ::Time.at(1_650_000_000) }
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_650_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    ensure
      Datadog::Core::Utils::Time.now_provider = -> { ::Time.now }
    end

    # Concern: detect runtime default from ABSENT variant, passed through as nil (aggregator decides).
    it 'passes a nil variant through unchanged (runtime-default signal preserved)' do
      details = instance_double(
        'OpenFeature::SDK::EvaluationDetails',
        variant: nil, reason: 'DEFAULT', flag_metadata: {},
      )
      expect(writer).to receive(:enqueue).with(hash_including(variant: nil))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it 'handles a nil evaluation_context without raising' do
      details = instance_double(
        'OpenFeature::SDK::EvaluationDetails',
        variant: 'v', reason: 'STATIC', flag_metadata: {},
      )
      ctx = double('HookContext', flag_key: 'f', evaluation_context: nil)
      expect(writer).to receive(:enqueue).with(hash_including(targeting_key: nil, attrs: {}))
      expect { hook.finally(hook_context: ctx, evaluation_details: details) }.not_to raise_error
    end
  end
end
