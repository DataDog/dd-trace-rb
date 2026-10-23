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
    describe "#get_assignment_with_options" do
      let(:configuration) { described_class::Configuration.new(JSON.generate(config)) }
      let(:config) { JSON.parse(flags_json) }
      let(:context) { {"targeting_key" => "subject", "email" => "user@example.com"} }

      before do
        unless described_class::Configuration.method_defined?(:get_assignment_with_options)
          skip "Requires a libdatadog build with evaluation options"
        end
        flag = config.fetch("flags").fetch("test-flag")
        flag["variations"]["ordinary"] = {"key" => "ordinary", "value" => {"feature" => "ordinary"}}
        flag["allocations"] << {
          "key" => "ordinary", "doLog" => false,
          "splits" => [{"variationKey" => "ordinary", "shards" => []}],
        }
      end

      [
        [{}, true, "treatment", true, nil],
        [{"dd_experimentation_opt_out_at" => "2026-10-01T00:00:00Z"}, true, "ordinary", false, nil],
        [{"dd_experimentation_opt_out_at" => "2099-01-01T01:02:03.123456789+05:30"}, true, "ordinary", false, nil],
        [{"dd_experimentation_opt_out_at" => ""}, true, nil, false, "INVALID_CONTEXT"],
        [{"dd_experimentation_opt_out_at" => "not-a-timestamp"}, true, nil, false, "INVALID_CONTEXT"],
        [{"dd_experimentation_opt_out_at" => true}, true, nil, false, "INVALID_CONTEXT"],
        [{"dd_experimentation_opt_out_at" => "not-a-timestamp"}, false, "treatment", true, nil],
      ].each do |attributes, immediate, variant, log_exposure, error_code|
        it "evaluates #{attributes.inspect} with immediate=#{immediate}" do
          result = configuration.get_assignment_with_options("test-flag", :object, context.merge(attributes), immediate)
          expect(result.variant).to eq(variant)
          expect(result.log?).to eq(log_exposure)
          expect(result.error_code).to eq(error_code)
        end
      end

      it "treats omitted doLog as an experiment allocation" do
        config["flags"]["test-flag"]["allocations"].first.delete("doLog")
        result = configuration.get_assignment_with_options(
          "test-flag", :object, context.merge("dd_experimentation_opt_out_at" => "2026-10-01T00:00:00Z"), true
        )
        expect(result.variant).to eq("ordinary")
        expect(result.log?).to be(false)
      end

      it "returns the default state when no ordinary allocation matches" do
        config["flags"]["test-flag"]["allocations"].pop
        result = configuration.get_assignment_with_options(
          "test-flag", :object, context.merge("dd_experimentation_opt_out_at" => "2026-10-01T00:00:00Z"), true
        )
        expect(result.variant).to be_nil
        expect(result.reason).to eq("DEFAULT")
        expect(result.log?).to be(false)
      end
    end

    describe "#get_assignment_with_opt_out_mode" do
      let(:configuration) { described_class::Configuration.new(JSON.generate(config)) }
      let(:config) { JSON.parse(flags_json) }
      let(:context) do
        {"targeting_key" => "subject", "email" => "user@example.com",
         "dd_experimentation_opt_out_at" => "2026-10-19T12:00:00Z"}
      end

      before do
        unless described_class::Configuration.method_defined?(:get_assignment_with_opt_out_mode)
          skip "Requires a libdatadog build with opt-out modes"
        end
        flag = config.fetch("flags").fetch("test-flag")
        flag["variations"]["ordinary"] = {"key" => "ordinary", "value" => {"feature" => "ordinary"}}
        flag["allocations"] << {
          "key" => "ordinary", "doLog" => false,
          "splits" => [{"variationKey" => "ordinary", "shards" => []}],
        }
      end

      [
        ["2026-10-19T11:59:59.999999999Z", true],
        ["2026-10-19T12:00:00Z", false],
        ["2026-10-19T12:00:00.000000001Z", false],
        ["2026-10-19T17:30:00+05:30", false],
        [nil, false],
      ].product([:disabled, :immediate, :future_experiments_only]).each do |(activation, older), mode|
        it "evaluates activation #{activation.inspect} in #{mode}" do
          config["flags"]["test-flag"]["allocations"].first["randomizationActivatedAt"] = activation
          result = configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, mode)
          experiment = mode == :disabled || (mode == :future_experiments_only && older)

          expect(result.variant).to eq(experiment ? "treatment" : "ordinary")
          expect(result.allocation_key).to eq(experiment ? "test-allocation" : "ordinary")
          expect(result.log?).to eq(experiment)
          expect(result.error_code).to be_nil
        end
      end

      it "excludes unknown activation but evaluates an absent subject attribute normally" do
        result = configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, :future_experiments_only)
        expect(result.variant).to eq("ordinary")
        expect(result.log?).to be(false)

        context.delete("dd_experimentation_opt_out_at")
        result = configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, :future_experiments_only)
        expect(result.variant).to eq("treatment")
        expect(result.log?).to be(true)
      end

      it "returns the default state when no ordinary allocation matches" do
        config["flags"]["test-flag"]["allocations"].pop
        result = configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, :future_experiments_only)
        expect(result.variant).to be_nil
        expect(result.reason).to eq("DEFAULT")
        expect(result.log?).to be(false)
      end

      ["", "invalid", true, 123].each do |input|
        it "rejects invalid subject input #{input.inspect}" do
          context["dd_experimentation_opt_out_at"] = input
          result = configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, :future_experiments_only)
          expect(result.error_code).to eq("INVALID_CONTEXT")
          expect(result.log?).to be(false)
        end
      end

      [:disabled, :immediate, :future_experiments_only].each do |mode|
        it "isolates malformed activation in #{mode}" do
          config["flags"]["neighbor"] = Marshal.load(Marshal.dump(config["flags"]["test-flag"]))
          config["flags"]["neighbor"]["key"] = "neighbor"
          config["flags"]["test-flag"]["allocations"].first["randomizationActivatedAt"] = "invalid"
          result = configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, mode)
          expect(result.error_code).to eq((mode == :future_experiments_only) ? "PARSE_ERROR" : nil)
          expect(result.variant).to eq({disabled: "treatment", immediate: "ordinary", future_experiments_only: nil}.fetch(mode))
          expect(result.log?).to eq(mode == :disabled)
          neighbor = configuration.get_assignment_with_opt_out_mode("neighbor", :object, context, mode)
          expect(neighbor.error_code).to be_nil
        end
      end

      it "rejects unsupported modes before native evaluation" do
        expect do
          configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, :unknown)
        end.to raise_error(ArgumentError, /Unsupported experimentation opt-out mode/)
        expect do
          configuration.get_assignment_with_opt_out_mode("test-flag", :object, context, "future_experiments_only")
        end.to raise_error(TypeError)
      end
    end

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
