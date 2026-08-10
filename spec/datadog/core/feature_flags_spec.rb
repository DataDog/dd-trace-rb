# frozen_string_literal: true

require "datadog/core"
require "datadog/core/feature_flags"
require "datadog/open_feature/native_evaluator"

RSpec.describe Datadog::Core::FeatureFlags do
  let(:flags_json) do
    <<~JSON
      {
        "id": "1",
        "createdAt": "2024-04-17T19:40:53.716Z",
        "format": "SERVER",
        "environment": {
          "name": "Test"
        },
        "flags": {
          "test-flag": {
            "key": "test-flag",
            "enabled": true,
            "variationType": "JSON",
            "variations": {
              "treatment": {
                "key": "treatment",
                "value": {"feature":"enabled","color":"blue","count":42}
              }
            },
            "allocations": [
              {
                "key": "test-allocation",
                "rules": [
                  {
                    "conditions": [
                      {
                        "attribute": "email",
                        "operator": "MATCHES",
                        "value": "@example\\\\.com"
                      }
                    ]
                  }
                ],
                "splits": [
                  {
                    "variationKey": "treatment",
                    "shards": []
                  }
                ],
                "doLog": true
              }
            ]
          }
        }
      }
    JSON
  end

  describe "Configuration" do
    describe ".new" do
      it "creates a new configuration from valid JSON" do
        expect { described_class::Configuration.new(flags_json) }.not_to raise_error
      end

      it "raises an error with invalid JSON" do
        expect { described_class::Configuration.new("invalid json") }
          .to raise_error(described_class::Error, /Failed to create configuration from JSON/)
      end
    end

    describe "#get_assignment" do
      subject(:configuration) { described_class::Configuration.new(flags_json) }

      context "when flag eveluatino was successfull" do
        let(:result) do
          configuration.get_assignment(
            "test-flag", :object, {"targeting_key" => "test-user", "email" => "user@example.com"}
          )
        end

        it "evaluates flag successfully and returns all expected fields" do
          expect(result.value).to eq({"feature" => "enabled", "color" => "blue", "count" => 42})
          expect(result.variant).to eq("treatment")
          expect(result.allocation_key).to eq("test-allocation")
          # serial_id is bound via the libdatadog FFI as an optional i32; this
          # fixture's split carries no serial id, so the NONE tag maps to nil.
          expect(result.serial_id).to be_nil
          expect(result.reason).to eq("TARGETING_MATCH")
          expect(result.log?).to be(true)
          expect(result.error?).to be(false)
          expect(result.error_code).to be_nil
          expect(result.error_message).to be_nil
        end
      end

      context "when flag is missing" do
        let(:result) do
          configuration.get_assignment(
            "non-existent-flag", :object, {"targeting_key" => "test-user", "email" => "user@example.com"}
          )
        end

        it "returns error details" do
          expect(result.error?).to be(true)
          expect(result.error_code).to eq("FLAG_NOT_FOUND")
          expect(result.reason).to eq("ERROR")
        end
      end

      context "when falling through all allocations" do
        let(:result) do
          configuration.get_assignment(
            "test-flag", :object, {"targeting_key" => "test-user", "email" => "user@different-domain.com"}
          )
        end

        it "returns default state with no assignment" do
          expect(result.reason).to eq("DEFAULT")
          expect(result.value).to be_nil
          expect(result.variant).to be_nil
          expect(result.allocation_key).to be_nil
          expect(result.serial_id).to be_nil
          expect(result.error?).to be(false)
          expect(result.log?).to be(false)
        end
      end

      context "when expected type is unknown" do
        let(:result) do
          configuration.get_assignment(
            "test-flag", :unknown_type, {"targeting_key" => "test-user", "email" => "user@example.com"}
          )
        end

        it "raises error for unknown type" do
          expect { result }.to raise_error(described_class::Error, /Unexpected flag type/)
        end
      end

      context "when value lazy evaluation fails" do
        before { allow(JSON).to receive(:parse).and_raise(JSON::ParserError, "Ooops") }

        let(:result) do
          configuration.get_assignment(
            "test-flag", :object, {"targeting_key" => "test-user", "email" => "user@example.com"}
          )
        end

        it "raises error for JSON parsing error" do
          expect { result.value }.to raise_error(described_class::Error, /Failed to parse JSON value/)
        end
      end
    end
  end
end

RSpec.describe Datadog::OpenFeature::NativeEvaluator do
  fixture_root = File.expand_path("../open_feature/ffe-system-test-data", __dir__)
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
            context: evaluation_context(test_case),
          )

          expected = test_case.fetch("result")

          expect(result.value).to eq(expected.fetch("value"))
          expect(result.reason).to eq(expected.fetch("reason"))
          expect(result.variant).to eq(expected["variant"]) if expected.key?("variant")
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
