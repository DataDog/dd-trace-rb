# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/hooks/debug_logging_hook"

RSpec.describe Datadog::OpenFeature::Hooks::DebugLoggingHook do
  subject(:hook) { described_class.new(logger) }

  let(:logger) { instance_double(Datadog::Core::Logger) }
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

  before { allow(logger).to receive(:debug) { |&block| debug_messages << block.call } }

  describe ".available?" do
    it { expect(described_class.available?).to be(true) }
  end

  describe "#finally" do
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

      it "does not log flag values, targeting keys, context attributes, or error messages" do
        hook.finally(hook_context: hook_context, evaluation_details: evaluation_details)

        expect(debug_messages.join).not_to include("private-flag-value", "jane.doe", "enterprise")
      end
    end

    context "without an evaluation context or flag metadata" do
      let(:evaluation_context) { nil }
      let(:resolution_details) do
        OpenFeature::SDK::Provider::ResolutionDetails.new(value: "control", reason: "ERROR", error_code: "GENERAL")
      end

      it "still logs the evaluation" do
        expect { hook.finally(hook_context: hook_context, evaluation_details: evaluation_details) }.not_to raise_error

        expect(debug_messages.size).to eq(1)
      end
    end
  end
end
