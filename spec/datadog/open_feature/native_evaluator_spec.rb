# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/native_evaluator"

RSpec.describe Datadog::OpenFeature::NativeEvaluator do
  before do
    stub_const("Datadog::Core::FeatureFlags::Configuration", configuration_class)
    allow(Datadog::Core::FeatureFlags::Configuration)
      .to receive(:new).and_return(configuration)
    allow(configuration).to receive(:get_assignment).with(flag_key, expected_type, context).and_return(assignment)
  end

  subject(:evaluator) { described_class.new(configuration_json) }

  let(:configuration_class) do
    Class.new do
      def initialize(_configuration)
      end

      def get_assignment(_flag_key, _expected_type, _context)
      end
    end
  end
  let(:configuration_json) { '{"flags":{}}' }
  let(:configuration) { configuration_class.new(configuration_json) }
  let(:flag_key) { "flag" }
  let(:expected_type) { :boolean }
  let(:context) { {"targeting_key" => "user-1"} }
  let(:assignment_class) do
    Class.new do
      attr_accessor :value
      attr_reader :reason, :error_code, :error_message, :variant

      def initialize(reason:, error_code:, error_message:, variant:)
        @reason = reason
        @error_code = error_code
        @error_message = error_message
        @variant = variant
      end
    end
  end
  let(:assignment) do
    assignment_class.new(reason: reason, error_code: error_code, error_message: error_message, variant: variant)
  end
  let(:reason) { "TARGETING_MATCH" }
  let(:error_code) { nil }
  let(:error_message) { nil }
  let(:variant) { "on" }

  describe "#get_assignment" do
    subject(:result) do
      evaluator.get_assignment(flag_key, default_value: false, expected_type: expected_type, context: context)
    end

    context "when libdatadog reports an invalid per-flag configuration as caller default" do
      let(:reason) { "DEFAULT" }
      let(:error_message) { "flag configuration is invalid or unsupported" }
      let(:variant) { nil }

      it "returns an OpenFeature parse error using the caller default" do
        expect(assignment).not_to receive(:value=)

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
        expect(assignment).to receive(:value=).with(false)

        expect(result).to be(assignment)
      end
    end
  end

  describe "#observe_full_evaluation_data" do
    def ufc(observe: :absent)
      base = "{\"format\":\"SERVER\",\"environment\":{\"name\":\"test\"},\"flags\":{}}"
      return base if observe == :absent

      value = (observe == true) ? "true" : "false"
      extra = "\"observeFullEvaluationData\":#{value}"
      base.sub('{"format"', "{#{extra},\"format\"")
    end

    it "returns false when the field is absent (privacy-preserving default)" do
      evaluator = described_class.new(ufc(observe: :absent))
      expect(evaluator.observe_full_evaluation_data).to be(false)
    end

    it "returns false when the field is false" do
      evaluator = described_class.new(ufc(observe: false))
      expect(evaluator.observe_full_evaluation_data).to be(false)
    end

    it "returns true when the field is true" do
      evaluator = described_class.new(ufc(observe: true))
      expect(evaluator.observe_full_evaluation_data).to be(true)
    end

    it "returns false when the field is explicit null" do
      json = '{"format":"SERVER","observeFullEvaluationData":null,"environment":{"name":"test"},"flags":{}}'
      evaluator = described_class.new(json)
      expect(evaluator.observe_full_evaluation_data).to be(false)
    end

    it "returns false when the field is wrong-typed (string)" do
      json = '{"format":"SERVER","observeFullEvaluationData":"true","environment":{"name":"test"},"flags":{}}'
      evaluator = described_class.new(json)
      expect(evaluator.observe_full_evaluation_data).to be(false)
    end

    it "reads the field from the UFC root, not from the environment object" do
      # The environment object does not carry the field; the root does.
      json = '{"format":"SERVER","observeFullEvaluationData":true,"environment":{"name":"test"},"flags":{}}'
      evaluator = described_class.new(json)
      expect(evaluator.observe_full_evaluation_data).to be(true)
    end

    it "returns false and does not raise on malformed JSON" do
      evaluator = described_class.new("{not valid json")
      expect(evaluator.observe_full_evaluation_data).to be(false)
    end

    it "returns false for a nil configuration" do
      evaluator = described_class.new(nil)
      expect(evaluator.observe_full_evaluation_data).to be(false)
    end
  end
end
