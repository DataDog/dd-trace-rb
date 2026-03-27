# frozen_string_literal: true

require 'datadog/core'
require 'datadog/core/feature_flags'

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

  describe 'Configuration' do
    describe '.new' do
      it 'creates a new configuration from valid JSON' do
        expect { described_class::Configuration.new(flags_json) }.not_to raise_error
      end

      it 'raises an error with invalid JSON' do
        expect { described_class::Configuration.new('invalid json') }
          .to raise_error(described_class::Error, /Failed to create configuration from JSON/)
      end
    end

    describe '#get_assignment' do
      subject(:configuration) { described_class::Configuration.new(flags_json) }

      context 'when flag eveluatino was successfull' do
        let(:result) do
          configuration.get_assignment(
            'test-flag', :object, {'targeting_key' => 'test-user', 'email' => 'user@example.com'}
          )
        end

        it 'evaluates flag successfully and returns all expected fields' do
          expect(result.value).to eq({'feature' => 'enabled', 'color' => 'blue', 'count' => 42})
          expect(result.variant).to eq('treatment')
          expect(result.allocation_key).to eq('test-allocation')
          expect(result.reason).to eq('TARGETING_MATCH')
          expect(result.log?).to be(true)
          expect(result.error?).to be(false)
          expect(result.error_code).to be_nil
          expect(result.error_message).to be_nil
        end
      end

      context 'when flag is missing' do
        let(:result) do
          configuration.get_assignment(
            'non-existent-flag', :object, {'targeting_key' => 'test-user', 'email' => 'user@example.com'}
          )
        end

        it 'returns error details' do
          expect(result.error?).to be(true)
          expect(result.error_code).to eq('FLAG_NOT_FOUND')
          expect(result.reason).to eq('ERROR')
        end
      end

      context 'when falling through all allocations' do
        let(:result) do
          configuration.get_assignment(
            'test-flag', :object, {'targeting_key' => 'test-user', 'email' => 'user@different-domain.com'}
          )
        end

        it 'returns default state with no assignment' do
          expect(result.reason).to eq('DEFAULT')
          expect(result.value).to be_nil
          expect(result.variant).to be_nil
          expect(result.allocation_key).to be_nil
          expect(result.error?).to be(false)
          expect(result.log?).to be(false)
        end
      end

      context 'when expected type is unknown' do
        let(:result) do
          configuration.get_assignment(
            'test-flag', :unknown_type, {'targeting_key' => 'test-user', 'email' => 'user@example.com'}
          )
        end

        it 'raises error for unknown type' do
          expect { result }.to raise_error(described_class::Error, /Unexpected flag type/)
        end
      end

      context 'when value lazy evaluation fails' do
        before { allow(JSON).to receive(:parse).and_raise(JSON::ParserError, 'Ooops') }

        let(:result) do
          configuration.get_assignment(
            'test-flag', :object, {'targeting_key' => 'test-user', 'email' => 'user@example.com'}
          )
        end

        it 'raises error for JSON parsing error' do
          expect { result.value }.to raise_error(described_class::Error, /Failed to parse JSON value/)
        end
      end

      context 'with null targeting key' do
        let(:null_tk_flags_json) do
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

        let(:null_tk_config) { described_class::Configuration.new(null_tk_flags_json) }

        it 'evaluates static flag successfully with nil targeting key' do
          result = null_tk_config.get_assignment('static-flag', :string, {})
          expect(result.value).to eq('static-value')
          expect(result.reason).to eq('STATIC')
          expect(result.error?).to be(false)
        end

        it 'returns TARGETING_KEY_MISSING for sharded flag with nil targeting key' do
          result = null_tk_config.get_assignment('sharded-flag', :string, {})
          expect(result.error?).to be(true)
          expect(result.error_code).to eq('TARGETING_KEY_MISSING')
        end

        it 'evaluates rule-match flag successfully with nil targeting key' do
          result = null_tk_config.get_assignment('rule-flag', :string, {'email' => 'user@example.com'})
          expect(result.value).to eq('rule-value')
          expect(result.reason).to eq('TARGETING_MATCH')
          expect(result.error?).to be(false)
        end
      end
    end
  end
end
