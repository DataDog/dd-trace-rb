# frozen_string_literal: true

require 'json'
require_relative '../../../../../lib/datadog/open_feature/binding/internal_evaluator'

RSpec.describe 'InternalEvaluator Rule Evaluation' do
  describe 'numeric comparison rules' do
    let(:flag_config) do
      {
        "flags" => {
          "age_gated_flag" => {
            "key" => "age_gated_flag",
            "enabled" => true,
            "variationType" => "BOOLEAN",
            "variations" => {
              "off" => { "key" => "off", "value" => false },
              "on" => { "key" => "on", "value" => true }
            },
            "allocations" => [
              {
                "key" => "adults_only",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "age",
                        "operator" => "GTE",
                        "value" => 18
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "on", "shards" => [] }]
              },
              {
                "key" => "default_allocation",
                "doLog" => false,
                "splits" => [{ "variationKey" => "off", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'passes rule for users meeting age requirement' do
      adult_context = { "age" => 25 }
      result = evaluator.get_assignment("age_gated_flag", adult_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(true)
      expect(result.flag_metadata['allocationKey']).to eq("adults_only")
      expect(result.reason).to eq("TARGETING_MATCH") # Has rules
    end

    it 'fails rule for users not meeting age requirement' do
      minor_context = { "age" => 16 }
      result = evaluator.get_assignment("age_gated_flag", minor_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
      expect(result.reason).to eq("STATIC") # No rules, single split
    end

    it 'fails rule when required attribute is missing' do
      no_age_context = { "name" => "John" }
      result = evaluator.get_assignment("age_gated_flag", no_age_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end
  end

  describe 'membership rules (ONE_OF)' do
    let(:flag_config) do
      {
        "flags" => {
          "tier_flag" => {
            "key" => "tier_flag",
            "enabled" => true,
            "variationType" => "STRING",
            "variations" => {
              "basic" => { "key" => "basic", "value" => "basic_features" },
              "premium" => { "key" => "premium", "value" => "premium_features" }
            },
            "allocations" => [
              {
                "key" => "premium_users",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "plan",
                        "operator" => "ONE_OF",
                        "value" => ["premium", "enterprise", "admin"]
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "premium", "shards" => [] }]
              },
              {
                "key" => "basic_users",
                "doLog" => false,
                "splits" => [{ "variationKey" => "basic", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'passes rule when attribute matches one of the values' do
      premium_context = { "plan" => "premium" }
      result = evaluator.get_assignment("tier_flag", premium_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("premium_features")
      expect(result.flag_metadata['allocationKey']).to eq("premium_users")
    end

    it 'passes rule when attribute matches another value in the list' do
      enterprise_context = { "plan" => "enterprise" }
      result = evaluator.get_assignment("tier_flag", enterprise_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("premium_features")
      expect(result.flag_metadata['allocationKey']).to eq("premium_users")
    end

    it 'fails rule when attribute does not match any value' do
      basic_context = { "plan" => "basic" }
      result = evaluator.get_assignment("tier_flag", basic_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("basic_features")
      expect(result.flag_metadata['allocationKey']).to eq("basic_users")
    end
  end

  describe 'multiple conditions in single rule' do
    let(:flag_config) do
      {
        "flags" => {
          "complex_rule_flag" => {
            "key" => "complex_rule_flag",
            "enabled" => true,
            "variationType" => "BOOLEAN",
            "variations" => {
              "off" => { "key" => "off", "value" => false },
              "on" => { "key" => "on", "value" => true }
            },
            "allocations" => [
              {
                "key" => "eligible_users",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "age",
                        "operator" => "GTE",
                        "value" => 18
                      },
                      {
                        "attribute" => "country",
                        "operator" => "ONE_OF",
                        "value" => ["US", "CA", "GB"]
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "on", "shards" => [] }]
              },
              {
                "key" => "default_allocation",
                "doLog" => false,
                "splits" => [{ "variationKey" => "off", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'passes rule when all conditions are met' do
      eligible_context = { "age" => 25, "country" => "US" }
      result = evaluator.get_assignment("complex_rule_flag", eligible_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(true)
      expect(result.flag_metadata['allocationKey']).to eq("eligible_users")
    end

    it 'fails rule when first condition fails' do
      young_us_context = { "age" => 16, "country" => "US" }
      result = evaluator.get_assignment("complex_rule_flag", young_us_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end

    it 'fails rule when second condition fails' do
      adult_non_us_context = { "age" => 25, "country" => "DE" }
      result = evaluator.get_assignment("complex_rule_flag", adult_non_us_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end

    it 'fails rule when both conditions fail' do
      ineligible_context = { "age" => 16, "country" => "DE" }
      result = evaluator.get_assignment("complex_rule_flag", ineligible_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end
  end

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
      result = evaluator.get_assignment("multi_rule_flag", admin_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("special_value")
      expect(result.flag_metadata['allocationKey']).to eq("special_users")
    end

    it 'matches allocation when second rule passes' do
      senior_context = { "user_type" => "regular", "age" => 70 }
      result = evaluator.get_assignment("multi_rule_flag", senior_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("special_value")
      expect(result.flag_metadata['allocationKey']).to eq("special_users")
    end

    it 'matches allocation when both rules pass' do
      admin_senior_context = { "user_type" => "admin", "age" => 70 }
      result = evaluator.get_assignment("multi_rule_flag", admin_senior_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("special_value")
      expect(result.flag_metadata['allocationKey']).to eq("special_users")
    end

    it 'uses fallback allocation when no rules pass' do
      regular_context = { "user_type" => "regular", "age" => 30 }
      result = evaluator.get_assignment("multi_rule_flag", regular_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("default_value")
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end
  end

  describe 'regex rules' do
    let(:flag_config) do
      {
        "flags" => {
          "regex_flag" => {
            "key" => "regex_flag",
            "enabled" => true,
            "variationType" => "BOOLEAN",
            "variations" => {
              "off" => { "key" => "off", "value" => false },
              "on" => { "key" => "on", "value" => true }
            },
            "allocations" => [
              {
                "key" => "email_users",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "email",
                        "operator" => "MATCHES",
                        "value" => ".*@example\\.com$"
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "on", "shards" => [] }]
              },
              {
                "key" => "default_allocation",
                "doLog" => false,
                "splits" => [{ "variationKey" => "off", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'matches when regex pattern matches' do
      matching_context = { "email" => "user@example.com" }
      result = evaluator.get_assignment("regex_flag", matching_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(true)
      expect(result.flag_metadata['allocationKey']).to eq("email_users")
    end

    it 'fails when regex pattern does not match' do
      non_matching_context = { "email" => "user@other.com" }
      result = evaluator.get_assignment("regex_flag", non_matching_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("default_allocation")
    end

    it 'handles invalid regex patterns gracefully' do
      # Create an evaluator that can test invalid regex directly
      test_evaluator = evaluator
      expect(test_evaluator.send(:evaluate_regex, "test", "[invalid", true)).to eq(false)
    end
  end

  describe 'null check rules' do
    let(:flag_config) do
      {
        "flags" => {
          "null_check_flag" => {
            "key" => "null_check_flag",
            "enabled" => true,
            "variationType" => "STRING",
            "variations" => {
              "has_value" => { "key" => "has_value", "value" => "user_has_attribute" },
              "no_value" => { "key" => "no_value", "value" => "user_missing_attribute" }
            },
            "allocations" => [
              {
                "key" => "users_with_phone",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "phone",
                        "operator" => "IS_NULL",
                        "value" => false
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "has_value", "shards" => [] }]
              },
              {
                "key" => "users_without_phone",
                "doLog" => false,
                "splits" => [{ "variationKey" => "no_value", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'matches when attribute exists (IS_NULL = false)' do
      has_phone_context = { "phone" => "+1234567890" }
      result = evaluator.get_assignment("null_check_flag", has_phone_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("user_has_attribute")
      expect(result.flag_metadata['allocationKey']).to eq("users_with_phone")
    end

    it 'fails when attribute is missing (IS_NULL = false)' do
      no_phone_context = { "email" => "user@example.com" }
      result = evaluator.get_assignment("null_check_flag", no_phone_context, :string, "default")
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq("user_missing_attribute")
      expect(result.flag_metadata['allocationKey']).to eq("users_without_phone")
    end
  end

  describe 'NOT_ONE_OF rules' do
    let(:flag_config) do
      {
        "flags" => {
          "exclusion_flag" => {
            "key" => "exclusion_flag",
            "enabled" => true,
            "variationType" => "BOOLEAN",
            "variations" => {
              "off" => { "key" => "off", "value" => false },
              "on" => { "key" => "on", "value" => true }
            },
            "allocations" => [
              {
                "key" => "non_blocked_users",
                "rules" => [
                  {
                    "conditions" => [
                      {
                        "attribute" => "country",
                        "operator" => "NOT_ONE_OF",
                        "value" => ["BLOCKED", "RESTRICTED"]
                      }
                    ]
                  }
                ],
                "doLog" => true,
                "splits" => [{ "variationKey" => "on", "shards" => [] }]
              },
              {
                "key" => "blocked_users",
                "doLog" => false,
                "splits" => [{ "variationKey" => "off", "shards" => [] }]
              }
            ]
          }
        }
      }
    end

    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'passes when attribute is not in blocked list' do
      allowed_context = { "country" => "US" }
      result = evaluator.get_assignment("exclusion_flag", allowed_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(true)
      expect(result.flag_metadata['allocationKey']).to eq("non_blocked_users")
    end

    it 'fails when attribute is in blocked list' do
      blocked_context = { "country" => "BLOCKED" }
      result = evaluator.get_assignment("exclusion_flag", blocked_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("blocked_users")
    end

    it 'fails when attribute is missing (NOT_ONE_OF fails for missing attributes)' do
      no_country_context = { "name" => "John" }
      result = evaluator.get_assignment("exclusion_flag", no_country_context, :boolean, false)
      
      expect(result.error_code).to be_nil
      expect(result.value).to eq(false)
      expect(result.flag_metadata['allocationKey']).to eq("blocked_users")
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
