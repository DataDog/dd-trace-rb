# frozen_string_literal: true

require "spec_helper"

# Tests run under the openfeature appraisal which includes the real OpenFeature SDK
require "open_feature/sdk"
require "datadog/open_feature/hooks/flag_eval_evp_hook"
require "datadog/open_feature/flag_evaluation/writer"

RSpec.describe Datadog::OpenFeature::Hooks::FlagEvalEVPHook do
  subject(:hook) { described_class.new(writer) }

  let(:writer) { instance_double(Datadog::OpenFeature::FlagEvaluation::Writer, enqueue: nil) }

  let(:eval_context) { ::OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-7", env: "prod") }
  let(:hook_context) { build_hook_context }

  def build_hook_context(flag_key: "my-flag", evaluation_context: eval_context)
    ::OpenFeature::SDK::Hooks::HookContext.new(
      flag_key: flag_key,
      flag_value_type: :string,
      default_value: "default",
      evaluation_context: evaluation_context,
    )
  end

  def build_evaluation_details(variant:, error_message: nil, error_code: nil, flag_metadata: {})
    ::OpenFeature::SDK::EvaluationDetails.new(
      flag_key: "my-flag",
      resolution_details: ::OpenFeature::SDK::Provider::ResolutionDetails.new(
        value: "default",
        variant: variant,
        error_message: error_message,
        error_code: error_code,
        flag_metadata: flag_metadata,
      ),
    )
  end

  describe "#finally — captures cheaply and enqueues (async boundary)" do
    let(:evaluation_details) do
      build_evaluation_details(
        variant: "on",
        flag_metadata: {
          "__dd_allocation_key" => "alloc-9",
          "dd.eval.timestamp_ms" => 1_700_000_000_000,
          Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => true,
        },
      )
    end

    # Variant comes from evaluation_details.variant (the OpenFeature variant), NEVER the value.
    # The hook is never given the evaluated value, so it cannot accidentally emit it.
    it "enqueues the variant from evaluation_details.variant" do
      expect(writer).to receive(:enqueue).with(hash_including(variant: "on"))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "enqueues runtime_default false for a successful variant result" do
      expect(writer).to receive(:enqueue).with(hash_including(runtime_default: false))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    # allocation_key read from metadata['__dd_allocation_key'] — the SAME source the OTel hook uses.
    it "enqueues allocation_key from the same metadata key the OTel hook reads" do
      expect(writer).to receive(:enqueue).with(hash_including(allocation_key: "alloc-9"))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    # eval-time read from the provider-stamped 'dd.eval.timestamp_ms' metadata key.
    it "enqueues eval_time_ms from the provider-stamped dd.eval.timestamp_ms metadata" do
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_700_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "enqueues flag_key, targeting_key and attrs without reason" do
      expect(writer).to receive(:enqueue) do |event|
        expect(event).to include(
          flag_key: "my-flag",
          targeting_key: "user-7",
          attrs: {"env" => "prod"},
        )
        expect(event).not_to have_key(:reason)
      end
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "extracts targeting key and attrs from a real SDK evaluation context" do
      sdk_context = ::OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-9", tier: "gold")
      hook_ctx = build_hook_context(evaluation_context: sdk_context)

      expect(writer).to receive(:enqueue).with(hash_including(targeting_key: "user-9", attrs: {"tier" => "gold"}))
      hook.finally(hook_context: hook_ctx, evaluation_details: evaluation_details)
    end

    it "enqueues error_message when present" do
      details = build_evaluation_details(variant: nil, error_message: "flag not found")
      expect(writer).to receive(:enqueue).with(hash_including(error_message: "flag not found"))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "does NOT touch the aggregator on the hook path (only enqueues — async boundary)" do
      # The hook collaborates ONLY with writer#enqueue; it has no aggregator reference at all.
      expect(hook.instance_variables).not_to include(:@aggregator)
      expect(writer).to receive(:enqueue).once
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end
  end

  describe "#finally — runtime-default + missing-metadata edge cases" do
    # Fallback: when the provider did not stamp a timestamp, fall back to hook-fire time.
    it "falls back to a real hook-fire timestamp when dd.eval.timestamp_ms is absent" do
      details = build_evaluation_details(variant: "on")
      allow(Datadog::Core::Utils::Time).to receive(:now).and_return(::Time.at(1_650_000_000))
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_650_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    # Concern: detect runtime default from ABSENT variant, passed through as nil (aggregator decides).
    it "passes a nil variant through unchanged (runtime-default signal preserved)" do
      details = build_evaluation_details(variant: nil)
      expect(writer).to receive(:enqueue).with(hash_including(variant: nil, runtime_default: true))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "marks type mismatch as runtime default even when the SDK exposes a variant" do
      details = build_evaluation_details(
        variant: "variant-a",
        error_code: ::OpenFeature::SDK::Provider::ErrorCode::TYPE_MISMATCH,
      )
      expect(writer).to receive(:enqueue).with(hash_including(variant: "variant-a", runtime_default: true))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "handles a nil evaluation_context without raising" do
      details = build_evaluation_details(variant: "v")
      ctx = build_hook_context(flag_key: "f", evaluation_context: nil)
      expect(writer).to receive(:enqueue).with(hash_including(targeting_key: nil, attrs: {}))
      expect { hook.finally(hook_context: ctx, evaluation_details: details) }.not_to raise_error
    end
  end

  describe "#finally — consent lifecycle" do
    let(:eval_context) { ::OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-7", env: "prod") }
    let(:hook_context) { build_hook_context }

    def details_with_consent(consent)
      metadata = {
        "dd.eval.timestamp_ms" => 1_700_000_000_000,
        Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => consent,
      }
      build_evaluation_details(variant: "on", flag_metadata: metadata)
    end

    it "reads consent from evaluation metadata, not from live config" do
      details = details_with_consent(true)
      expect(writer).to receive(:enqueue).with(
        hash_including(observe_full_evaluation_data: true, attrs: {"env" => "prod"})
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "treats absent consent as false (privacy-preserving default)" do
      details = build_evaluation_details(variant: "on", flag_metadata: {"dd.eval.timestamp_ms" => 1})
      expect(writer).to receive(:enqueue).with(
        hash_including(observe_full_evaluation_data: false, attrs: {})
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "treats null consent as false" do
      details = details_with_consent(nil)
      expect(writer).to receive(:enqueue).with(
        hash_including(observe_full_evaluation_data: false, attrs: {})
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "treats wrong-typed consent as false" do
      details = details_with_consent("true")
      expect(writer).to receive(:enqueue).with(
        hash_including(observe_full_evaluation_data: false, attrs: {})
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    # Regression guard for the Java pilot's core lesson: consent must travel on the
    # event, not be looked up from live config. The hook reads only metadata.
    it "ignores gateway consent even when it disagrees with metadata" do
      details = details_with_consent(false)
      # Even if a global accessor returned true, the hook must use metadata's false.
      expect(writer).to receive(:enqueue).with(
        hash_including(observe_full_evaluation_data: false, attrs: {})
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "passes the error code so the writer can redact the error message" do
      details = build_evaluation_details(
        variant: nil, error_message: "boom", error_code: "TYPE_MISMATCH",
        flag_metadata: {"dd.eval.timestamp_ms" => 1}
      )
      expect(writer).to receive(:enqueue).with(hash_including(error_code: "TYPE_MISMATCH"))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end
  end
end
