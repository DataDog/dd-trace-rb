# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/native_evaluator"

RSpec.describe Datadog::OpenFeature::NativeEvaluator do
  before do
    allow(Datadog::Core::FeatureFlags::Configuration)
      .to receive(:new).and_return(configuration)
    allow(configuration).to receive(:get_assignment).with(flag_key, expected_type, context).and_return(assignment)
  end

  subject(:evaluator) { described_class.new(configuration_json) }

  let(:resolution_details_class) do
    Class.new do
      attr_reader(
        :value,
        :reason,
        :error_code,
        :error_message,
        :variant,
        :flag_metadata,
        :allocation_key,
        :serial_id,
      )

      def log?
      end

      def error?
      end
    end
  end
  let(:configuration_json) { '{"flags":{}}' }
  let(:configuration) do
    instance_double(Datadog::Core::FeatureFlags::Configuration, observe_full_evaluation_data: observe_full_evaluation_data)
  end
  let(:observe_full_evaluation_data) { false }
  let(:flag_key) { "flag" }
  let(:expected_type) { :boolean }
  let(:context) { {"targeting_key" => "user-1"} }
  let(:assignment) do
    instance_double(
      resolution_details_class,
      value: value,
      reason: reason,
      error_code: error_code,
      error_message: error_message,
      variant: variant,
      flag_metadata: flag_metadata,
      allocation_key: allocation_key,
      serial_id: serial_id,
      log?: log,
      error?: error,
    )
  end
  let(:value) { true }
  let(:reason) { "TARGETING_MATCH" }
  let(:error_code) { nil }
  let(:error_message) { nil }
  let(:variant) { "on" }
  let(:flag_metadata) { {"native" => "kept"} }
  let(:allocation_key) { "allocation-1" }
  let(:serial_id) { 123 }
  let(:log) { true }
  let(:error) { false }

  describe "#get_assignment" do
    subject(:result) do
      evaluator.get_assignment(flag_key, default_value: false, expected_type: expected_type, context: context)
    end

    it "copies the native assignment into OpenFeature resolution details" do
      expect(result).to be_a(Datadog::OpenFeature::ResolutionDetails)
      expect(result.value).to be(true)
      expect(result.reason).to eq("TARGETING_MATCH")
      expect(result.variant).to eq("on")
      expect(result.error_code).to be_nil
      expect(result.error_message).to be_nil
      expect(result.flag_metadata).to eq("native" => "kept")
      expect(result.allocation_key).to eq("allocation-1")
      expect(result.serial_id).to eq(123)
      expect(result.log?).to be(true)
      expect(result.error?).to be(false)
    end

    context "when the native assignment has an object value" do
      let(:expected_type) { :object }
      let(:value) { {"feature" => "enabled"} }

      it "copies the parsed object value" do
        expect(result.value).to eq("feature" => "enabled")
      end
    end

    context "when libdatadog reports an invalid per-flag configuration as caller default" do
      let(:reason) { "DEFAULT" }
      let(:error_message) { "flag configuration is invalid or unsupported" }
      let(:variant) { nil }

      it "returns an OpenFeature parse error using the caller default" do
        expect(result.value).to be(false)
        expect(result.reason).to eq("ERROR")
        expect(result.error_code).to eq("PARSE_ERROR")
        expect(result.error_message).to eq("flag configuration is invalid or unsupported")
        expect(result.error?).to be(true)
      end
    end

    context "when libdatadog reports an ordinary default result" do
      let(:reason) { "DEFAULT" }
      let(:error_message) { "default allocation is matched and is serving NULL" }
      let(:variant) { nil }

      it "keeps the default result and applies the caller default value" do
        expect(result).to be_a(Datadog::OpenFeature::ResolutionDetails)
        expect(result.value).to be(false)
        expect(result.reason).to eq("DEFAULT")
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to eq("native" => "kept")
      end
    end
  end

  describe "#observe_full_evaluation_data" do
    subject(:observe) { evaluator.observe_full_evaluation_data }

    context "when the native configuration opts in" do
      let(:observe_full_evaluation_data) { true }

      it { is_expected.to be(true) }
    end

    context "when the native configuration does not opt in" do
      it { is_expected.to be(false) }
    end
  end

  describe "opt-out context validation" do
    [:immediate, :future_experiments_only].product(
      [nil, true, false, 123, [], {}, "2026-10-01T00:00:00Z\0suffix", "\xFF".b,
        (+"\xFF").force_encoding(Encoding::UTF_8), "2026-10-01T00:00:00Z".encode(Encoding::UTF_16LE)]
    ).each do |mode, invalid_value|
      it "rejects #{invalid_value.inspect} before native context conversion in #{mode}" do
        result = evaluator.get_assignment(
          flag_key, default_value: false, expected_type: expected_type,
          context: context.merge("dd_experimentation_opt_out_at" => invalid_value),
          experimentation_opt_out_mode: mode
        )

        expect(result.value).to be(false)
        expect(result.error_code).to eq("INVALID_CONTEXT")
        expect(result.error_message).to include(
          "dd_experimentation_opt_out_at", "RFC3339", "supply a valid timestamp", "omit the attribute",
        )
        expect(result.error_message).not_to include("suffix")
        expect(result.log?).to be(false)
        expect(configuration).not_to have_received(:get_assignment)
      end
    end
  end
end

RSpec.describe Datadog::OpenFeature::NativeEvaluator, "shared opt-out policy" do
  cases = File.readlines(File.join(__dir__, "fixtures", "experimentation-opt-out-policy.jsonl"))
    .map { |line| JSON.parse(line) }
  raise "Expected all 90 shared policy cases" unless cases.size == 90

  subject(:evaluator) { described_class.new(JSON.generate(configuration)) }

  before do
    unless Datadog::Core::FeatureFlags::Configuration.method_defined?(:get_assignment_with_opt_out_mode)
      skip "Requires a libdatadog build with opt-out modes"
    end
  end

  let(:configuration) do
    {
      "createdAt" => "2026-01-01T00:00:00Z", "environment" => {"name" => "test"},
      "flags" => {"feature" => {
        "key" => "feature", "enabled" => true, "variationType" => "STRING",
        "variations" => {
          "experiment" => {"key" => "experiment", "value" => "experiment"},
          "ordinary" => {"key" => "ordinary", "value" => "ordinary"},
        },
        "allocations" => [
          {"key" => "candidate", "doLog" => false, "splits" => [{"variationKey" => "experiment", "shards" => []}]},
          {"key" => "fallback", "doLog" => false, "splits" => [{"variationKey" => "ordinary", "shards" => []}]},
        ],
      }},
    }
  end

  cases.each do |test_case|
    it "evaluates #{test_case.fetch("id")} through the native extension" do
      args = test_case.fetch("args")
      expected = test_case.fetch("expected")
      allocation = configuration["flags"]["feature"]["allocations"].first
      allocation["doLog"] = args.fetch("doLog")
      activation = {
        "missing" => nil, "invalid" => "invalid", "before" => "2025-12-31T23:59:59.999999999Z",
        "equal" => "2026-01-01T00:00:00Z", "after" => "2026-01-01T00:00:00.000000001Z",
      }.fetch(args.fetch("activation"))
      allocation["randomizationActivatedAt"] = activation unless activation.nil?
      context = {"targeting_key" => "subject"}
      case args.fetch("attribute")
      when "valid" then context["dd_experimentation_opt_out_at"] = "2026-01-01T00:00:00Z"
      when "invalid" then context["dd_experimentation_opt_out_at"] = true
      end

      result = evaluator.get_assignment(
        "feature", default_value: "default", expected_type: :string, context: context,
        experimentation_opt_out_mode: args.fetch("mode").to_sym,
      )
      if expected.fetch("error") == "NONE"
        variant = expected.fetch("exclude") ? "ordinary" : "experiment"
        expect(result.value).to eq(variant)
        expect(result.variant).to eq(variant)
        expect(result.allocation_key).to eq(expected.fetch("exclude") ? "fallback" : "candidate")
        expect(result.error_code).to be_nil
        expect(result.log?).to eq(args.fetch("doLog") && !expected.fetch("exclude"))
      else
        expect(result.value).to eq("default")
        expect(result.error_code).to eq(expected.fetch("error"))
        expect(result.variant).to be_nil
        expect(result.allocation_key).to be_nil
        expect(result.log?).to be(false)
      end
    end
  end
end
