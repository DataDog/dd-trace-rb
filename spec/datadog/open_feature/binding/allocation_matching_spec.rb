# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'datadog/open_feature/binding/internal_evaluator'

RSpec.describe 'InternalEvaluator Allocation Matching' do
  describe 'time-based allocation filtering' do
    let(:flag_config) do
      {
        "flags" => {
          "time_test_flag" => {
            "key" => "time_test_flag",
            "enabled" => true,
            "variationType" => "STRING", 
            "variations" => {
              "control" => { "key" => "control", "value" => "control_value" },
              "treatment" => { "key" => "treatment", "value" => "treatment_value" }
            },
            "allocations" => [
              {
                "key" => "expired_allocation",
                "endAt" => (Time.now - 3600).to_i, # Expired 1 hour ago
                "doLog" => true,
                "splits" => [
                  { "variationKey" => "control", "shards" => [] }
                ]
              },
              {
                "key" => "active_allocation", 
                "doLog" => false,
                "splits" => [
                  { "variationKey" => "treatment", "shards" => [] }
                ]
              }
            ]
          }
        }
      }
    end
    
    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new(flag_config.to_json) }

    it 'skips expired allocations and uses active ones' do
      result = evaluator.get_assignment("time_test_flag", {}, :string)
      
      expect(result.error_code).to be_nil  # nil for successful evaluation
      expect(result.value).to eq("treatment_value") # Should use active allocation
      expect(result.variant).to eq("treatment")
      expect(result.flag_metadata['allocation_key']).to eq("active_allocation")
      expect(result.flag_metadata['do_log']).to eq(false)
    end

    it 'returns assignment reason based on allocation properties' do
      result = evaluator.get_assignment("time_test_flag", {}, :string)
      
      expect(result.reason).to eq("STATIC") # Single split with no shards = static
    end
  end

  describe 'default value integration' do
    let(:evaluator) { Datadog::OpenFeature::Binding::InternalEvaluator.new('{"flags": {}}') }

    it 'returns error result on flag lookup errors' do
      result = evaluator.get_assignment("missing_flag", {}, :string)
      
      expect(result.error_code).to eq(:flag_not_found) 
      expect(result.value).to be_nil  # Internal evaluator returns nil, provider handles defaults
      expect(result.variant).to be_nil
      expect(result.flag_metadata).to eq({})
    end

    it 'returns consistent error results for different types' do
      string_result = evaluator.get_assignment("missing", {}, :string)
      number_result = evaluator.get_assignment("missing", {}, :float)
      bool_result = evaluator.get_assignment("missing", {}, :boolean)
      
      expect(string_result.value).to be_nil  # Internal evaluator returns nil
      expect(number_result.value).to be_nil
      expect(bool_result.value).to be_nil
      expect(string_result.error_code).to eq(:flag_not_found)
      expect(number_result.error_code).to eq(:flag_not_found)
      expect(bool_result.error_code).to eq(:flag_not_found)
    end
  end

  describe 'allocation reason classification' do
    it 'returns TARGETING_MATCH for allocations with time bounds' do
      config_with_time_bounds = {
        "flags" => {
          "timed_flag" => {
            "key" => "timed_flag",
            "enabled" => true,
            "variationType" => "BOOLEAN",
            "variations" => { "var1" => { "key" => "var1", "value" => true } },
            "allocations" => [
              {
                "key" => "timed_allocation",
                "startAt" => (Time.now - 3600).to_i, # Started 1 hour ago
                "endAt" => (Time.now + 3600).to_i,   # Ends 1 hour from now  
                "doLog" => true,
                "splits" => [{ "variationKey" => "var1", "shards" => [] }]
              }
            ]
          }
        }
      }
      
      evaluator = Datadog::OpenFeature::Binding::InternalEvaluator.new(config_with_time_bounds.to_json)
      result = evaluator.get_assignment("timed_flag", {}, :boolean)
      
      expect(result.error_code).to be_nil  # nil for successful evaluation
      expect(result.reason).to eq("TARGETING_MATCH") # Has time bounds
      expect(result.variant).not_to be_nil
      expect(result.flag_metadata).not_to be_nil
    end
  end
end
