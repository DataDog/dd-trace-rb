# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'datadog/open_feature/binding/internal_evaluator'

RSpec.describe 'InternalEvaluator Rule Evaluation' do
  # Most rule evaluation scenarios are covered by UFC test cases:
  # - GTE/comparison operators: test-case-comparator-operator-flag.json
  # - ONE_OF membership: test-case-boolean-one-of-matches.json  
  # - Regex matching: test-case-regex-flag.json
  # - Null checks: test-case-null-operator-flag.json
  # 
  # The following tests cover scenarios not fully exercised by UFC test cases:

  describe 'multiple rules in allocation (OR logic)' do
    let(:flag_config) do
      {
        "flags" => {
          "multi_rule_flag" => {
            "key" => "multi_rule_flag",
            "enabled" => true,
            "variationType" => "STRING",
            "variations" => {
              "default" => { "key" => "default", "value" => "default_value" },
              "special" => { "key" => "special", "value" => "special_value" }
            },
            "allocations" => [
              {
                "key" => "special_users",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "user_type",
                        "operator" => "ONE_OF",
                        "value" => ["admin", "moderator"]
                      }
                    ]
                  },
                  {
                    "conditions" => [
                      {
                        "attribute" => "age",
                        "operator" => "GTE",
                        "value" => 65
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "special", "shards" => [] }]
              },
              {
                "key" => "default_allocation",
                "doLog" => false,
                "splits" => [{ "variationKey" => "default", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'matches allocation when first rule passes' do
      admin_context = { "user_type" => "admin", "age" => 30 }
      result = evaluator.get_assignment("multi_rule_flag", admin_context, :string)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("special_value")
      expect(result.flag_metadata['allocationKey']).to eq("special_users")
    end

    it 'matches allocation when second rule passes' do
      senior_context = { "user_type" => "regular", "age" => 70 }
      result = evaluator.get_assignment("multi_rule_flag", senior_context, :string)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("special_value")
      expect(result.flag_metadata['allocationKey']).to eq("special_users")
    end

    it 'matches allocation when both rules pass' do
      admin_senior_context = { "user_type" => "admin", "age" => 70 }
      result = evaluator.get_assignment("multi_rule_flag", admin_senior_context, :string)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("special_value")
      expect(result.flag_metadata['allocationKey']).to eq("special_users")
    end

    it 'uses fallback allocation when no rules pass' do
      regular_context = { "user_type" => "regular", "age" => 30 }
      result = evaluator.get_assignment("multi_rule_flag", regular_context, :string)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("default_value")
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end
  end

  describe 'invalid regex patterns' do
    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new('{"flags": {}}') }

    it 'handles invalid regex patterns gracefully' do
      # Test the error handling for malformed regex patterns
      expect(evaluator.send(:evaluate_regex, "test", "[invalid", true)).to eq(false)
      expect(evaluator.send(:evaluate_regex, "test", "*invalid", false)).to eq(false)
    end
  end

  describe 'NOT_ONE_OF edge cases' do
    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new('{"flags": {}}') }

    it 'fails when attribute is missing (NOT_ONE_OF fails for missing attributes)' do
      # Test the specific behavior that NOT_ONE_OF fails when attribute is nil
      expect(evaluator.send(:evaluate_membership, nil, ["value"], false)).to eq(false)
    end
  end

  describe 'type coercion' do
    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new('{"flags": {}}') }

    it 'coerces numeric strings for comparison' do
      # Test the coercion logic directly
      expect(evaluator.send(:coerce_to_number, "25")).to eq(25.0)
      expect(evaluator.send(:coerce_to_number, "3.14")).to eq(3.14)
      expect(evaluator.send(:coerce_to_number, "invalid")).to be_nil
    end

    it 'coerces values to strings for membership tests' do
      expect(evaluator.send(:coerce_to_string, 42)).to eq("42")
      expect(evaluator.send(:coerce_to_string, true)).to eq("true")
      expect(evaluator.send(:coerce_to_string, false)).to eq("false")
    end

    it 'handles boolean coercion for null checks' do
      expect(evaluator.send(:coerce_to_boolean, true)).to eq(true)
      expect(evaluator.send(:coerce_to_boolean, "true")).to eq(true)
      expect(evaluator.send(:coerce_to_boolean, "false")).to eq(false)
      expect(evaluator.send(:coerce_to_boolean, 1)).to eq(true)
      expect(evaluator.send(:coerce_to_boolean, 0)).to eq(false)
    end
  end
end
