# frozen_string_literal: true

require "datadog/core"
require "datadog/core/feature_flags"

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

    describe "#observe_full_evaluation_data" do
      subject(:observe_full_evaluation_data) { configuration.observe_full_evaluation_data }

      let(:configuration) { described_class::Configuration.new(JSON.generate(config)) }
      let(:config) { JSON.parse(flags_json) }

      it "defaults to false when absent" do
        is_expected.to be(false)
      end

      context "when enabled" do
        before { config["observeFullEvaluationData"] = true }

        it { is_expected.to be(true) }
      end

      context "when the field has the malformed value from FFL-3125" do
        before { config["observeFullEvaluationData"] = 42 }

        it { is_expected.to be(false) }
      end
    end

    describe "#get_assignment" do
      subject(:configuration) { described_class::Configuration.new(flags_json) }

      context "when flag eveluatino was successfull" do
        let(:result) do
          configuration.get_assignment(
            "test-flag", :object, {"targeting_key" => "test-user", "email" => "user@example.com"},
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
            "non-existent-flag", :object, {"targeting_key" => "test-user", "email" => "user@example.com"},
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
            "test-flag", :object, {"targeting_key" => "test-user", "email" => "user@different-domain.com"},
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
            "test-flag", :unknown_type, {"targeting_key" => "test-user", "email" => "user@example.com"},
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
            "test-flag", :object, {"targeting_key" => "test-user", "email" => "user@example.com"},
          )
        end

        it "raises error for JSON parsing error" do
          expect { result.value }.to raise_error(described_class::Error, /Failed to parse JSON value/)
        end
      end
    end

    describe "ResolutionDetails#features" do
      subject(:features) do
        described_class::Configuration.new(JSON.generate(config))
          .get_assignment("split-flag", :string, {"targeting_key" => "subject"})
          .features
      end

      let(:split) { {"variationKey" => "on", "shards" => []} }
      let(:config) do
        {
          "createdAt" => "2024-04-17T19:40:53.716Z",
          "environment" => {"name" => "Test"},
          "flags" => {
            "split-flag" => {
              "key" => "split-flag",
              "enabled" => true,
              "variationType" => "STRING",
              "variations" => {"on" => {"key" => "on", "value" => "enabled"}},
              "allocations" => [{"key" => "allocation", "splits" => [split], "doLog" => true}],
            },
          },
        }
      end

      context "when the split has features of every supported value type" do
        let(:split) do
          {
            "variationKey" => "on",
            "shards" => [],
            "features" => [
              {"key" => "holdout.key", "value" => "h-1", "destinations" => ["HOOK"]},
              {"key" => "holdout.share", "value" => 0.25, "destinations" => ["EXPOSURE", "EVALUATION"]},
              {"key" => "holdout.should_include_in_holdout_analysis", "value" => false, "destinations" => ["HOOK"]},
            ],
          }
        end

        it "returns key, typed value and destinations in configuration order" do
          expect(features).to eq(
            [
              ["holdout.key", "h-1", ["HOOK"]],
              ["holdout.share", 0.25, ["EXPOSURE", "EVALUATION"]],
              ["holdout.should_include_in_holdout_analysis", false, ["HOOK"]],
            ],
          )
          expect(features.first.first.encoding).to eq(Encoding::UTF_8)
          expect(features.first[1]).to be_frozen
        end
      end

      context "when a feature has an unsupported value type" do
        let(:split) do
          {
            "variationKey" => "on",
            "shards" => [],
            "features" => [
              {"key" => "object", "value" => {"nested" => true}, "destinations" => ["HOOK"]},
              {"key" => "kept", "value" => "yes", "destinations" => ["HOOK"]},
            ],
          }
        end

        it "skips only that feature" do
          expect(features).to eq([["kept", "yes", ["HOOK"]]])
        end
      end

      context "when a key repeats" do
        let(:split) do
          {
            "variationKey" => "on",
            "shards" => [],
            "features" => [
              {"key" => "holdout.key", "value" => {"invalid" => true}, "destinations" => ["HOOK"]},
              {"key" => "holdout.key", "value" => "first-valid", "destinations" => ["HOOK"]},
              {"key" => "holdout.key", "value" => "second-valid", "destinations" => ["HOOK", "EXPOSURE"]},
            ],
          }
        end

        it "keeps the first valid feature" do
          expect(features).to eq([["holdout.key", "first-valid", ["HOOK"]]])
        end
      end

      context "when destinations are unknown to the SDK" do
        let(:split) do
          {
            "variationKey" => "on",
            "shards" => [],
            "features" => [{"key" => "holdout.key", "value" => "h-1", "destinations" => ["hook", "FUTURE"]}],
          }
        end

        it "passes them through unchanged" do
          expect(features).to eq([["holdout.key", "h-1", ["hook", "FUTURE"]]])
        end
      end

      [
        ["missing", nil],
        ["null", :null],
        ["not a list", {"key" => "holdout.key"}],
        ["a list of malformed entries", ["holdout.key", 1, nil, {"key" => "no-value"}]],
      ].each do |description, raw_features|
        context "when the features field is #{description}" do
          let(:split) do
            base = {"variationKey" => "on", "shards" => []}
            base["features"] = (raw_features == :null) ? nil : raw_features unless raw_features.nil?
            base
          end

          it "evaluates the flag and returns the shared frozen empty array" do
            result = described_class::Configuration.new(JSON.generate(config))
              .get_assignment("split-flag", :string, {"targeting_key" => "subject"})

            expect(result.value).to eq("enabled")
            expect(result.error_code).to be_nil
            expect(result.features).to eq([])
            expect(result.features).to be_frozen
            expect(result.features).to be(features)
          end
        end
      end
    end
  end
end
