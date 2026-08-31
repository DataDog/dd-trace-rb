# frozen_string_literal: true

require "spec_helper"

# Tests run under the openfeature appraisal which includes the real OpenFeature SDK
require "open_feature/sdk"
require "datadog/open_feature/hooks/flag_eval_evp_hook"
require "datadog/open_feature/flag_evaluation/writer"

RSpec.describe Datadog::OpenFeature::Hooks::FlagEvalEVPHook do
  subject(:hook) { described_class.new(writer) }

  let(:documented_error_codes) do
    %w[
      PROVIDER_NOT_READY
      FLAG_NOT_FOUND
      PARSE_ERROR
      TYPE_MISMATCH
      TARGETING_KEY_MISSING
      INVALID_CONTEXT
      PROVIDER_FATAL
      GENERAL
    ]
  end
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

  def build_evaluation_details(
    variant:, reason: "TARGETING_MATCH", error_message: nil, error_code: nil, flag_metadata: {}
  )
    ::OpenFeature::SDK::EvaluationDetails.new(
      flag_key: "my-flag",
      resolution_details: ::OpenFeature::SDK::Provider::ResolutionDetails.new(
        value: "default",
        reason: reason,
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

    # The hook is never given the evaluated value, so it cannot accidentally emit it.
    it "enqueues the variant from evaluation_details.variant" do
      expect(writer).to receive(:enqueue).with(hash_including(variant: "on"))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "enqueues runtime_default false for a successful variant result" do
      expect(writer).to receive(:enqueue).with(hash_including(runtime_default: false))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "enqueues allocation_key from the same metadata key the OTel hook reads" do
      expect(writer).to receive(:enqueue).with(hash_including(allocation_key: "alloc-9"))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "enqueues eval_time_ms from the provider-stamped dd.eval.timestamp_ms metadata" do
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_700_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "enqueues flag_key, targeting_key and attrs without reason" do
      expect(writer).to receive(:enqueue) do |event|
        expect(event).to include(
          flag_key: "my-flag",
          targeting_key: "user-7",
          attrs: {"targeting_key" => "user-7", "env" => "prod"},
        )
        expect(event).not_to have_key(:reason)
      end
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end

    it "does NOT touch the aggregator on the hook path (only enqueues — async boundary)" do
      expect(hook.instance_variables).not_to include(:@aggregator)
      expect(writer).to receive(:enqueue).once
      hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
    end
  end

  describe "#finally — runtime-default + missing-metadata edge cases" do
    it "falls back to a real hook-fire timestamp when dd.eval.timestamp_ms is absent" do
      details = build_evaluation_details(variant: "on")
      allow(Datadog::Core::Utils::Time).to receive(:now).and_return(::Time.at(1_650_000_000))
      expect(writer).to receive(:enqueue).with(hash_including(eval_time_ms: 1_650_000_000_000))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "marks a DEFAULT reason as runtime default" do
      details = build_evaluation_details(variant: nil, reason: "DEFAULT")
      expect(writer).to receive(:enqueue).with(hash_including(variant: nil, runtime_default: true))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "does not infer a runtime default from a nil variant without DEFAULT or ERROR reason" do
      details = build_evaluation_details(variant: nil, reason: "DISABLED")
      expect(writer).to receive(:enqueue).with(hash_including(runtime_default: false))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "marks an ERROR reason as runtime default and omits stale variant and allocation data" do
      details = build_evaluation_details(
        variant: "variant-a",
        reason: "ERROR",
        error_code: ::OpenFeature::SDK::Provider::ErrorCode::TYPE_MISMATCH,
        flag_metadata: {"__dd_allocation_key" => "alloc-9"},
      )
      expect(writer).to receive(:enqueue).with(
        hash_including(
          variant: nil,
          allocation_key: nil,
          error_message: "TYPE_MISMATCH",
          runtime_default: true,
        )
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "handles a nil evaluation_context without raising" do
      details = build_evaluation_details(variant: "v")
      ctx = build_hook_context(flag_key: "f", evaluation_context: nil)
      expect(writer).to receive(:enqueue).with(hash_including(targeting_key: nil, attrs: nil))
      expect { hook.finally(hook_context: ctx, evaluation_details: details) }.not_to raise_error
    end
  end

  describe "#finally — observe_full_evaluation_data lifecycle" do
    let(:eval_context) { ::OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-7", env: "prod") }
    let(:hook_context) { build_hook_context }

    def details_with_observe_full_evaluation_data(observe_full_evaluation_data)
      metadata = {
        "dd.eval.timestamp_ms" => 1_700_000_000_000,
        Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => observe_full_evaluation_data,
      }
      build_evaluation_details(variant: "on", flag_metadata: metadata)
    end

    it "reads observe_full_evaluation_data from evaluation metadata, not from live config" do
      details = details_with_observe_full_evaluation_data(true)
      expect(writer).to receive(:enqueue).with(
        hash_including(
          observe_full_evaluation_data: true,
          attrs: {"targeting_key" => "user-7", "env" => "prod"}
        )
      )
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "treats every value except true as a privacy-preserving false" do
      details = [
        build_evaluation_details(variant: "on", flag_metadata: {"dd.eval.timestamp_ms" => 1}),
        details_with_observe_full_evaluation_data(false),
        details_with_observe_full_evaluation_data(nil),
        details_with_observe_full_evaluation_data("true"),
      ]

      details.each do |evaluation_details|
        expect(writer).to receive(:enqueue).with(
          hash_including(observe_full_evaluation_data: false, attrs: nil)
        )
        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)
      end
    end

    it "uses the error code regardless of observe_full_evaluation_data" do
      [false, true].each do |observe_full_evaluation_data|
        details = build_evaluation_details(
          variant: nil,
          reason: "ERROR",
          error_message: "user jane.doe@datadoghq.com not in segment",
          error_code: "FLAG_NOT_FOUND",
          flag_metadata: {
            "dd.eval.timestamp_ms" => 1,
            Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => observe_full_evaluation_data,
          }
        )
        expect(writer).to receive(:enqueue).with(hash_including(error_message: "FLAG_NOT_FOUND"))
        hook.finally(hook_context: hook_context, evaluation_details: details)
      end
    end

    it "uses GENERAL for an ERROR reason without an error code" do
      details = build_evaluation_details(
        variant: nil,
        reason: "ERROR",
        error_message: "user jane.doe@datadoghq.com not in segment",
        error_code: nil,
        flag_metadata: {
          "dd.eval.timestamp_ms" => 1,
          Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => true,
        }
      )
      expect(writer).to receive(:enqueue).with(hash_including(error_message: "GENERAL"))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "omits a native informational message for a non-error DEFAULT result" do
      details = build_evaluation_details(
        variant: nil,
        reason: "DEFAULT",
        error_message: "default allocation is matched and is serving NULL",
        flag_metadata: {
          "dd.eval.timestamp_ms" => 1,
          Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => true,
        }
      )
      expect(writer).to receive(:enqueue).with(hash_including(error_message: nil))
      hook.finally(hook_context: hook_context, evaluation_details: details)
    end

    it "configures exactly the documented OpenFeature error codes" do
      expect(Datadog::OpenFeature::Ext::STANDARD_ERROR_CODES).to eq(documented_error_codes)
    end

    it "preserves every documented OpenFeature error code" do
      documented_error_codes.each do |error_code|
        details = build_evaluation_details(
          variant: nil,
          reason: "ERROR",
          error_message: "raw message",
          error_code: error_code,
          flag_metadata: {"dd.eval.timestamp_ms" => 1},
        )
        expect(writer).to receive(:enqueue).with(hash_including(error_message: error_code))
        hook.finally(hook_context: hook_context, evaluation_details: details)
      end
    end
  end
end
