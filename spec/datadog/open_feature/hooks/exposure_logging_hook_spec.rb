# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/hooks/exposure_logging_hook"
require "datadog/open_feature/exposures/reporter"

RSpec.describe Datadog::OpenFeature::Hooks::ExposureLoggingHook do
  subject(:hook) { described_class.new(reporter, telemetry: telemetry, logger: logger) }

  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter, record: false) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }
  let(:evaluation_context) { OpenFeature::SDK::EvaluationContext.new(targeting_key: "subject-1") }
  let(:hook_context) do
    OpenFeature::SDK::Hooks::HookContext.new(
      flag_key: "flag", flag_value_type: :string, default_value: "fallback", evaluation_context: evaluation_context,
    )
  end
  let(:metadata) do
    {
      "__dd_allocation_key" => "allocation",
      "__dd_do_log" => true,
      "__dd_split_serial_id" => 7,
      "__dd_exposure_feature.holdout.key" => "h-1",
      "__dd_feature.holdout.key" => "hook-only",
    }
  end
  let(:error_code) { nil }
  let(:reason) { "STATIC" }
  let(:variant) { "on" }
  let(:evaluation_details) do
    OpenFeature::SDK::EvaluationDetails.new(
      flag_key: "flag",
      resolution_details: OpenFeature::SDK::Provider::ResolutionDetails.new(
        value: "enabled", variant: variant, reason: reason, error_code: error_code, flag_metadata: metadata,
      ),
    )
  end

  def finally
    hook.finally(hook_context: hook_context, evaluation_details: evaluation_details, hints: nil)
  end

  it "records the exposure with its EXPOSURE features and stamps the verdict" do
    allow(reporter).to receive(:record).and_return(true)

    finally

    expect(reporter).to have_received(:record).with(
      flag_key: "flag", allocation_key: "allocation", variant: "on", serial_id: 7,
      context: evaluation_context, features: {"holdout.key" => "h-1"},
    )
    expect(metadata["__dd_exposure_cache_hit"]).to be(true)
  end

  {
    "the evaluation has an error code" => {error_code: "GENERAL"},
    "the reason is ERROR" => {reason: "ERROR"},
    "there is no variant" => {variant: nil},
  }.each do |description, overrides|
    context "when #{description}" do
      overrides.each { |name, value| let(name) { value } }

      it "records nothing" do
        finally

        expect(reporter).not_to have_received(:record)
        expect(metadata).not_to have_key("__dd_exposure_cache_hit")
      end
    end
  end

  context "when the allocation does not log exposures" do
    before { metadata.delete("__dd_do_log") }

    it "records nothing" do
      finally

      expect(reporter).not_to have_received(:record)
    end
  end

  context "when there is no allocation key" do
    before { metadata.delete("__dd_allocation_key") }

    it "records nothing" do
      finally

      expect(reporter).not_to have_received(:record)
    end
  end

  context "without an evaluation context" do
    let(:evaluation_context) { nil }

    it "records nothing" do
      finally

      expect(reporter).not_to have_received(:record)
    end
  end

  context "when the metadata is frozen" do
    before { metadata.freeze }

    it "records nothing, since the verdict could not be stamped" do
      finally

      expect(reporter).not_to have_received(:record)
    end
  end

  context "when recording raises" do
    let(:error) { RuntimeError.new("boom") }

    before { allow(reporter).to receive(:record).and_raise(error) }

    it "contains the error and reports it" do
      expect { finally }.not_to raise_error

      expect(telemetry).to have_received(:report).with(error, description: "OpenFeature: Failed to report exposure")
    end
  end
end
