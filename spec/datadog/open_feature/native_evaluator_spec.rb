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
  let(:configuration) { configuration_class.new(configuration_json) }
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
    let(:base_ufc) { '{"format":"SERVER","environment":{"name":"test"},"flags":{}}' }

    context "when the field is absent (privacy-preserving default)" do
      it { expect(described_class.new(base_ufc).observe_full_evaluation_data).to be(false) }
    end

    context "when the field is false" do
      let(:ufc) { '{"observeFullEvaluationData":false,"format":"SERVER","environment":{"name":"test"},"flags":{}}' }
      it { expect(described_class.new(ufc).observe_full_evaluation_data).to be(false) }
    end

    context "when the UFC root field is true" do
      let(:ufc) { '{"observeFullEvaluationData":true,"format":"SERVER","environment":{"name":"test"},"flags":{}}' }
      it { expect(described_class.new(ufc).observe_full_evaluation_data).to be(true) }
    end

    context "when the field is explicit null" do
      let(:ufc) { '{"format":"SERVER","observeFullEvaluationData":null,"environment":{"name":"test"},"flags":{}}' }
      it { expect(described_class.new(ufc).observe_full_evaluation_data).to be(false) }
    end

    context "when the field is wrong-typed (string)" do
      let(:ufc) { '{"format":"SERVER","observeFullEvaluationData":"true","environment":{"name":"test"},"flags":{}}' }
      it { expect(described_class.new(ufc).observe_full_evaluation_data).to be(false) }
    end

    context "when the JSON is malformed" do
      it { expect(described_class.new("{not valid json").observe_full_evaluation_data).to be(false) }
    end

    context "when the configuration is nil" do
      it { expect(described_class.new(nil).observe_full_evaluation_data).to be(false) }
    end
  end
end
