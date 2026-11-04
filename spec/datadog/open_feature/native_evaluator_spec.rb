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
        :dependency_evaluations,
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
      dependency_evaluations: [],
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

    context "with a prerequisite result" do
      let(:dependency) do
        instance_double(
          resolution_details_class,
          value: false, reason: dependency_reason, variant: dependency_variant,
          error_code: nil, error_message: nil, flag_metadata: {}, allocation_key: nil,
          serial_id: nil, log?: false, error?: false,
        )
      end
      let(:dependency_reason) { "DEFAULT" }
      let(:dependency_variant) { nil }

      before do
        allow(assignment).to receive(:dependency_evaluations).and_return([["parent", dependency, false]])
      end

      ["DISABLED", "DEFAULT"].each do |native_reason|
        context "when the prerequisite has no assignment with reason #{native_reason}" do
          let(:dependency_reason) { native_reason }

          it "normalizes the prerequisite to an error" do
            key, details, eligible = result.dependency_evaluations.fetch(0)
            expect(key).to eq("parent")
            expect(eligible).to be(false)
            expect(details.value).to be_nil
            expect(details.reason).to eq("ERROR")
            expect(details.error_code).to eq("GENERAL")
            expect(details.error_message).to eq("prerequisite has no assignment")
            expect(details.error?).to be(true)
            expect(details.log?).to be(false)
          end
        end
      end

      context "when the prerequisite has a default allocation assignment" do
        let(:dependency_variant) { "off" }

        it "preserves the assigned variant and default reason" do
          details = result.dependency_evaluations.fetch(0).fetch(1)
          expect(details.variant).to eq("off")
          expect(details.reason).to eq("DEFAULT")
          expect(details.error_code).to be_nil
          expect(details.error?).to be(false)
        end
      end

      context "when the prerequisite has a nested JSON value" do
        let(:dependency_reason) { "STATIC" }
        let(:dependency_variant) { "on" }

        it "copies assignment metadata without parsing a nested JSON value" do
          allow(dependency).to receive(:value).and_raise(Datadog::Core::FeatureFlags::Error, "JSON nesting exceeds the parser limit")
          allow(dependency).to receive(:flag_metadata).and_return("native" => "kept")
          allow(dependency).to receive(:allocation_key).and_return("parent-allocation")
          allow(dependency).to receive(:serial_id).and_return(42)
          allow(dependency).to receive(:log?).and_return(true)

          key, details, eligible = result.dependency_evaluations.fetch(0)

          expect(result.value).to be(true)
          expect(key).to eq("parent")
          expect(eligible).to be(false)
          expect(details.variant).to eq("on")
          expect(details.reason).to eq("STATIC")
          expect(details.error_code).to be_nil
          expect(details.error?).to be(false)
          expect(details.allocation_key).to eq("parent-allocation")
          expect(details.serial_id).to eq(42)
          expect(details.log?).to be(true)
          expect(details.flag_metadata).to eq("native" => "kept")
          expect(dependency).not_to have_received(:value)
        end
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
  context "with native prerequisite evaluation" do
    let(:configuration_json) { File.read(File.expand_path("../../fixtures/ffe/dependent_flags.json", __dir__)) }

    before do
      allow(Datadog::Core::FeatureFlags::Configuration).to receive(:new).and_call_original
      skip "requires the prerequisite-aware native library" unless Datadog::Core::FeatureFlags.evaluator_capabilities.include?("dependent-flag-variant-key-v1")
    end

    it "returns each prerequisite once and preserves exposure metadata after GC" do
      result = evaluator.get_assignment("root", default_value: false, expected_type: :boolean, context: context)
      GC.start
      expect(result.value).to be(true)
      expect(result.dependency_evaluations.size).to eq(1)
      key, dependency, eligible = result.dependency_evaluations.first
      expect(key).to eq("parent")
      expect(dependency.variant).to eq("on")
      expect(dependency.allocation_key).to eq("parent-allocation")
      expect(dependency.log?).to be(true)
      expect(eligible).to be(true)
    end

    it "keeps a rejected prerequisite evaluation but suppresses its exposure" do
      result = evaluator.get_assignment("rejected", default_value: true, expected_type: :boolean, context: context)
      expect(result.value).to be(false)
      expect(result.dependency_evaluations.map { |key, _details, eligible| [key, eligible] }).to eq([["parent", false]])
    end

    ["missing", "cycle", "requires-disabled"].each do |key|
      it "returns the caller default when #{key} cannot be evaluated" do
        result = evaluator.get_assignment(key, default_value: false, expected_type: :boolean, context: context)
        expect(result.value).to be(false)
        expect(result.error?).to be(true)
        if key == "cycle"
          expect(result.dependency_evaluations).to be_empty # The root is not counted again as a prerequisite.
        else
          expect(result.dependency_evaluations).not_to be_empty
        end
        expect(result.dependency_evaluations.map { |_key, _details, eligible| eligible }).to all(be(false))
        expect(evaluator.get_assignment("parent", default_value: false, expected_type: :boolean, context: context).value).to be(true)
      end
    end

    ["disabled", "unassigned"].each do |failure|
      context "when a reached prerequisite is #{failure}" do
        let(:configuration_json) do
          configuration = JSON.parse(super())
          parent = configuration.fetch("flags").fetch("parent")
          if failure == "disabled"
            parent["enabled"] = false
          else
            parent["allocations"] = []
          end
          JSON.generate(configuration)
        end

        it "reports the prerequisite failure and preserves direct evaluation behavior" do
          result = evaluator.get_assignment("root", default_value: false, expected_type: :boolean, context: context)
          expect(result.value).to be(false)
          expect(result.error_code).to eq("GENERAL")
          key, dependency, eligible = result.dependency_evaluations.fetch(0)
          expect(key).to eq("parent")
          expect(eligible).to be(false)
          expect(dependency.reason).to eq("ERROR")
          expect(dependency.error_code).to eq("GENERAL")
          expect(dependency.error?).to be(true)

          direct = evaluator.get_assignment("parent", default_value: false, expected_type: :boolean, context: context)
          expect(direct.value).to be(false)
          expect(direct.reason).to eq((failure == "disabled") ? "DISABLED" : "DEFAULT")
          expect(direct.error_code).to be_nil
          expect(direct.error?).to be(false)
        end
      end
    end
  end
end
