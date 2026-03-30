# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/feature_flags'

# Tests for OpenFeature spec OF.2: optional targeting key
# See: https://openfeature.dev/specification/sections/evaluation-context#requirement-311
#
# When targeting key is missing (nil), SDKs must still attempt evaluation:
# - Static flags (no shards): return value normally
# - Sharded flags: return TARGETING_KEY_MISSING error
# - Rule-match flags (no shards): return value if rule matches on non-id attribute

RSpec.describe 'OpenFeature OF.2: Optional Targeting Key' do
  before do
    skip 'Requires native libdatadog extension' unless Datadog::Core::FeatureFlags::Configuration.method(:new).arity == 1
  end

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

  context 'with nil targeting key' do
    it 'evaluates static flag successfully' do
      result = config.get_assignment('static-flag', :string, {})
      expect(result.value).to eq('static-value')
      expect(result.reason).to eq('STATIC')
      expect(result.error?).to be(false)
    end

    it 'returns TARGETING_KEY_MISSING for sharded flag' do
      result = config.get_assignment('sharded-flag', :string, {})
      expect(result.error?).to be(true)
      expect(result.error_code).to eq('TARGETING_KEY_MISSING')
    end

    it 'evaluates rule-match flag when rule matches on non-id attribute' do
      result = config.get_assignment('rule-flag', :string, {'email' => 'user@example.com'})
      expect(result.value).to eq('rule-value')
      expect(result.reason).to eq('TARGETING_MATCH')
      expect(result.error?).to be(false)
    end
  end
end
