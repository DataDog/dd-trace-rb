# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/feature_flags'

# The OpenFeature evaluation context makes the targeting key optional
# (Requirement 3.1.1). These examples verify flag evaluation across static,
# sharded, and rule-match flags for an absent targeting key (omitted or explicit
# nil) and for an empty string. The two differ on sharded flags: an absent key
# cannot be sharded (TARGETING_KEY_MISSING), whereas an empty string is a present
# key that gets hashed.
# See: https://openfeature.dev/specification/sections/evaluation-context#requirement-311

RSpec.describe 'Datadog Provider OF.2: Optional Targeting Key' do
  let(:flags_json) do
    <<~JSON
      {
        "id": "1",
        "createdAt": "2024-04-17T19:40:53.716Z",
        "format": "SERVER",
        "environment": {"name": "Test"},
        "flags": {
          "static-flag": {
            "key": "static-flag",
            "enabled": true,
            "variationType": "STRING",
            "variations": {"on": {"key": "on", "value": "static-value"}},
            "allocations": [{"key": "static-alloc", "splits": [{"variationKey": "on", "shards": []}], "doLog": false}]
          },
          "sharded-flag": {
            "key": "sharded-flag",
            "enabled": true,
            "variationType": "STRING",
            "variations": {"on": {"key": "on", "value": "sharded-value"}},
            "allocations": [{"key": "sharded-alloc", "splits": [{"variationKey": "on", "shards": [{"salt": "test-salt", "totalShards": 10000, "ranges": [{"start": 0, "end": 5000}]}]}], "doLog": false}]
          },
          "rule-flag": {
            "key": "rule-flag",
            "enabled": true,
            "variationType": "STRING",
            "variations": {"matched": {"key": "matched", "value": "rule-value"}},
            "allocations": [{"key": "rule-alloc", "rules": [{"conditions": [{"attribute": "email", "operator": "MATCHES", "value": "@example\\\\.com"}]}], "splits": [{"variationKey": "matched", "shards": []}], "doLog": false}]
          }
        }
      }
    JSON
  end

  let(:config) { Datadog::Core::FeatureFlags::Configuration.new(flags_json) }

  # An absent targeting key -- omitted, or an explicit nil -- cannot be sharded,
  # so sharded flags report TARGETING_KEY_MISSING; static and rule-match flags
  # still evaluate.
  shared_examples 'an absent targeting key' do
    it 'evaluates a static flag' do
      result = config.get_assignment('static-flag', :string, base_context)
      expect(result.value).to eq('static-value')
      expect(result.reason).to eq('STATIC')
      expect(result.error?).to be(false)
    end

    it 'returns TARGETING_KEY_MISSING for a sharded flag' do
      result = config.get_assignment('sharded-flag', :string, base_context)
      expect(result.error?).to be(true)
      expect(result.error_code).to eq('TARGETING_KEY_MISSING')
    end

    it 'evaluates a rule-match flag on a non-id attribute' do
      result = config.get_assignment('rule-flag', :string, base_context.merge('email' => 'user@example.com'))
      expect(result.value).to eq('rule-value')
      expect(result.reason).to eq('TARGETING_MATCH')
      expect(result.error?).to be(false)
    end
  end

  context 'with no targeting key in the evaluation context' do
    let(:base_context) { {} }

    it_behaves_like 'an absent targeting key'
  end

  context 'with an explicit nil targeting key' do
    let(:base_context) { {'targeting_key' => nil} }

    it_behaves_like 'an absent targeting key'
  end

  context 'with an empty string targeting key' do
    let(:base_context) { {'targeting_key' => ''} }

    it 'evaluates a static flag' do
      result = config.get_assignment('static-flag', :string, base_context)
      expect(result.value).to eq('static-value')
      expect(result.reason).to eq('STATIC')
      expect(result.error?).to be(false)
    end

    it 'treats the empty string as a present key on a sharded flag (no TARGETING_KEY_MISSING)' do
      # "" hashes outside the flag's 0-5000 shard range, so it falls through to
      # the flag default rather than being rejected as a missing key.
      result = config.get_assignment('sharded-flag', :string, base_context)
      expect(result.error?).to be(false)
      expect(result.error_code).to be_nil
      expect(result.reason).to eq('DEFAULT')
    end

    it 'evaluates a rule-match flag on a non-id attribute' do
      result = config.get_assignment('rule-flag', :string, base_context.merge('email' => 'user@example.com'))
      expect(result.value).to eq('rule-value')
      expect(result.reason).to eq('TARGETING_MATCH')
      expect(result.error?).to be(false)
    end
  end
end
