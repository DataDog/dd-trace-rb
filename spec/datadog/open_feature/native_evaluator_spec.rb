# frozen_string_literal: true

require "json"
require "spec_helper"
require "datadog/open_feature/native_evaluator"

RSpec.describe Datadog::OpenFeature::NativeEvaluator do
  before do
    stub_const("Datadog::Core::FeatureFlags::Configuration", configuration_class)
    allow(Datadog::Core::FeatureFlags::Configuration)
      .to receive(:new).with(configuration_json).and_return(configuration)
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
end

RSpec.describe Datadog::OpenFeature::NativeEvaluator do
  fixture_root = File.expand_path("ffe-system-test-data", __dir__)
  fixture_files = Dir[File.join(fixture_root, "evaluation-cases", "*.json")].sort

  raise "FFE fixture submodule is missing or empty" if fixture_files.empty?

  subject(:evaluator) { described_class.new(configuration) }

  let(:configuration) { File.read(File.join(fixture_root, "ufc-config.json")) }

  describe "canonical FFE fixtures" do
    fixture_files.each do |fixture_file|
      JSON.parse(File.read(fixture_file)).each_with_index do |test_case, index|
        it "evaluates #{File.basename(fixture_file)}[#{index}]" do
          result = evaluator.get_assignment(
            test_case.fetch("flag"),
            default_value: test_case.fetch("defaultValue"),
            expected_type: expected_type(test_case.fetch("variationType")),
            context: evaluation_context(test_case)
          )

          expected = test_case.fetch("result")

          expect(result.value).to eq(expected.fetch("value"))
          expect(result.reason).to eq(expected.fetch("reason"))
          expect(result.variant).to eq(expected["variant"])
          expect(result.error_code).to eq(expected["errorCode"]) if expected.key?("errorCode")
        end
      end
    end
  end

  def expected_type(variation_type)
    case variation_type
    when "BOOLEAN"
      :boolean
    when "STRING"
      :string
    when "INTEGER"
      :integer
    when "NUMERIC"
      :number
    when "JSON"
      :object
    else
      raise "Unsupported variation type: #{variation_type}"
    end
  end

  def evaluation_context(test_case)
    {"targeting_key" => test_case["targetingKey"]}.merge(test_case.fetch("attributes") || {})
  end
end
