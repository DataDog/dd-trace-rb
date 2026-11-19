# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/hooks/debug_logging_hook"

RSpec.describe Datadog::OpenFeature::Hooks::DebugLoggingHook do
  subject(:hook) { described_class.new(logger) }

  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, debug?: true) }
  let(:debug_messages) { [] }
  let(:hook_context) do
    OpenFeature::SDK::Hooks::HookContext.new(
      flag_key: "checkout-redesign",
      flag_value_type: :string,
      default_value: "control",
      evaluation_context: evaluation_context,
    )
  end
  let(:evaluation_details) do
    OpenFeature::SDK::EvaluationDetails.new(flag_key: "checkout-redesign", resolution_details: resolution_details)
  end

  before { allow(logger).to receive(:debug) { |message, &block| debug_messages << (block ? block.call : message) } }

  describe ".available?" do
    it { expect(described_class.available?).to be(true) }
  end

  describe "#finally" do
    context "when debug logging is disabled" do
      let(:output) { StringIO.new }
      let(:logger) { Datadog::Core::Logger.new(output) }
      let(:hook_context) { instance_double(OpenFeature::SDK::Hooks::HookContext) }
      let(:evaluation_details) { instance_double(OpenFeature::SDK::EvaluationDetails) }

      before { allow(logger).to receive(:debug).and_call_original }

      it "does not read the evaluation context or format the result" do
        expect(hook_context).not_to receive(:evaluation_context)
        expect(evaluation_details).not_to receive(:value)
        expect(evaluation_details).not_to receive(:flag_metadata)

        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)

        expect(output.string).to eq("")
      end
    end

    context "with an evaluation context and flag metadata" do
      let(:evaluation_context) do
        OpenFeature::SDK::EvaluationContext.new(
          targeting_key: "jane.doe@example.com",
          email: "jane.doe@example.com",
          plan: "enterprise",
        )
      end
      let(:resolution_details) do
        OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: "private-flag-value",
          variant: "treatment",
          reason: "TARGETING_MATCH",
          error_message: "failed for jane.doe@example.com",
          flag_metadata: {Datadog::OpenFeature::Ext::METADATA_ALLOCATION_KEY => "rollout"},
        )
      end

      it "logs the raw SDK-final evaluation details" do
        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)

        expect(debug_messages).to eq([
          'Feature Flags: evaluated "checkout-redesign" (type=string, default="control", ' \
            'value="private-flag-value", variant="treatment", reason="TARGETING_MATCH", allocation="rollout", ' \
            'error_code=nil, error_message="failed for jane.doe@example.com", ' \
            'targeting_key="jane.doe@example.com", ' \
            "attributes=#{{"email" => "jane.doe@example.com", "plan" => "enterprise"}.inspect}, " \
            "flag_metadata=#{{Datadog::OpenFeature::Ext::METADATA_ALLOCATION_KEY => "rollout"}.inspect})",
        ])
      end

      it "logs a large nested value in full" do
        large_value = {"rules" => Array.new(100) { |index| {"id" => index, "tags" => ["a" * 50]} }}
        large_details = OpenFeature::SDK::EvaluationDetails.new(
          flag_key: "checkout-redesign",
          resolution_details: OpenFeature::SDK::Provider::ResolutionDetails.new(value: large_value, reason: "STATIC"),
        )

        hook.finally(hook_context: hook_context, evaluation_details: large_details)

        expect(debug_messages.first).to include("value=#{large_value.inspect}")
      end
    end

    context "without an evaluation context or flag metadata" do
      let(:evaluation_context) { nil }
      let(:resolution_details) do
        OpenFeature::SDK::Provider::ResolutionDetails.new(value: "control", reason: "ERROR", error_code: "GENERAL")
      end

      it "still logs the evaluation" do
        expect { hook.finally(hook_context: hook_context, evaluation_details: evaluation_details) }.not_to raise_error

        expect(debug_messages).to eq([
          'Feature Flags: evaluated "checkout-redesign" (type=string, default="control", value="control", ' \
            'variant=nil, reason="ERROR", allocation=nil, error_code="GENERAL", error_message=nil, ' \
            "targeting_key=nil, attributes={}, flag_metadata=#{resolution_details.flag_metadata.inspect})",
        ])
      end
    end
  end
end
