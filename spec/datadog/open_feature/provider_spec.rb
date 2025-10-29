# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/provider'
require 'datadog/open_feature/evaluator'

RSpec.describe Datadog::OpenFeature::Provider do
  let(:provider) { described_class.new }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  before { allow(telemetry).to receive(:report) }

  describe '#fetch_boolean_value' do
    context 'when evaluator is not configured' do
      it 'returns default value with error details' do
        result = provider.fetch_boolean_value(flag_key: 'flag', default_value: false)

        expect(result.value).to eq(false)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when evaluator is configured' do
      before do
        evaluator = Datadog::OpenFeature::Evaluator.new(telemetry)
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)

        provider.init
      end

      let(:result) { provider.fetch_boolean_value(flag_key: 'flag', default_value: false) }
      let(:ufc) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "flags": {
                  "boolean_flag": {
                    "key": "flag",
                    "enabled": true,
                    "variationType": "BOOLEAN",
                    "variations": {
                      "control": { "key": "control", "value": true }
                    },
                    "allocations": [
                      {
                        "key": "rollout",
                        "splits": [{ "variationKey": "control", "shards": [] }],
                        "doLog": false
                      }
                    ]
                  }
                }
              }
            }
          }
        JSON
      end

      it 'returns flag result details' do
        expect(result.value).to be(true)
        expect(result.reason).to eq('hardcoded')
      end
    end
  end

  describe '#fetch_string_value' do
    context 'when evaluator is not configured' do
      it 'returns default value with error details' do
        result = provider.fetch_string_value(flag_key: 'flag', default_value: 'default')

        expect(result.value).to eq('default')
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when evaluator is configured' do
      before do
        evaluator = Datadog::OpenFeature::Evaluator.new(telemetry)
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)

        provider.init
      end

      let(:result) { provider.fetch_string_value(flag_key: 'flag', default_value: 'default') }
      let(:ufc) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "flags": {
                  "string_flag": {
                    "key": "flag",
                    "enabled": true,
                    "variationType": "STRING",
                    "variations": {
                      "control": { "key": "control", "value": "hello" }
                    },
                    "allocations": [
                      {
                        "key": "rollout",
                        "splits": [{ "variationKey": "control", "shards": [] }],
                        "doLog": false
                      }
                    ]
                  }
                }
              }
            }
          }
        JSON
      end

      it 'returns flag result details' do
        expect(result.value).to eq('hello')
        expect(result.reason).to eq('hardcoded')
      end
    end
  end

  describe '#fetch_number_value' do
    context 'when evaluator is not configured' do
      it 'returns default value with error details' do
        result = provider.fetch_number_value(flag_key: 'flag', default_value: 0)

        expect(result.value).to eq(0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when evaluator is configured' do
      before do
        evaluator = Datadog::OpenFeature::Evaluator.new(telemetry)
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)

        provider.init
      end

      let(:result) { provider.fetch_number_value(flag_key: 'flag', default_value: 0) }
      let(:ufc) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "flags": {
                  "number_flag": {
                    "key": "flag",
                    "enabled": true,
                    "variationType": "NUMBER",
                    "variations": {
                      "control": { "key": "control", "value": 1000 }
                    },
                    "allocations": [
                      {
                        "key": "rollout",
                        "splits": [{ "variationKey": "control", "shards": [] }],
                        "doLog": false
                      }
                    ]
                  }
                }
              }
            }
          }
        JSON
      end

      it 'returns flag result details' do
        expect(result.value).to eq(9000)
        expect(result.reason).to eq('hardcoded')
      end
    end
  end

  describe '#fetch_integer_value' do
    context 'when evaluator is not configured' do
      it 'returns default value with error details' do
        result = provider.fetch_integer_value(flag_key: 'flag', default_value: 1)

        expect(result.value).to eq(1)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when evaluator is configured' do
      before do
        evaluator = Datadog::OpenFeature::Evaluator.new(telemetry)
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)

        provider.init
      end

      let(:result) { provider.fetch_integer_value(flag_key: 'flag', default_value: 1) }
      let(:ufc) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "flags": {
                  "integer_flag": {
                    "key": "flag",
                    "enabled": true,
                    "variationType": "INTEGER",
                    "variations": {
                      "control": { "key": "control", "value": 21 }
                    },
                    "allocations": [
                      {
                        "key": "rollout",
                        "splits": [{ "variationKey": "control", "shards": [] }],
                        "doLog": false
                      }
                    ]
                  }
                }
              }
            }
          }
        JSON
      end

      it 'returns flag result details' do
        expect(result.value).to eq(42)
        expect(result.reason).to eq('hardcoded')
      end
    end
  end

  describe '#fetch_float_value' do
    context 'when evaluator is not configured' do
      it 'returns default value with error details' do
        result = provider.fetch_float_value(flag_key: 'flag', default_value: 0.0)

        expect(result.value).to eq(0.0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when evaluator is configured' do
      before do
        evaluator = Datadog::OpenFeature::Evaluator.new(telemetry)
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)

        provider.init
      end

      let(:result) { provider.fetch_float_value(flag_key: 'flag', default_value: 0.0) }
      let(:ufc) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "flags": {
                  "float_flag": {
                    "key": "flag",
                    "enabled": true,
                    "variationType": "FLOAT",
                    "variations": {
                      "control": { "key": "control", "value": 12.5 }
                    },
                    "allocations": [
                      {
                        "key": "rollout",
                        "splits": [{ "variationKey": "control", "shards": [] }],
                        "doLog": false
                      }
                    ]
                  }
                }
              }
            }
          }
        JSON
      end

      it 'returns flag result details' do
        expect(result.value).to eq(36.6)
        expect(result.reason).to eq('hardcoded')
      end
    end
  end

  describe '#fetch_object_value' do
    context 'when evaluator is not configured' do
      it 'returns default value with error details' do
        result = provider.fetch_object_value(flag_key: 'flag', default_value: { 'default' => true })

        expect(result.value).to eq({ 'default' => true })
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when evaluator is configured' do
      before do
        evaluator = Datadog::OpenFeature::Evaluator.new(telemetry)
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)

        provider.init
      end

      let(:result) { provider.fetch_object_value(flag_key: 'flag', default_value: { 'default' => true }) }
      let(:ufc) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "flags": {
                  "object_flag": {
                    "key": "flag",
                    "enabled": true,
                    "variationType": "OBJECT",
                    "variations": {
                      "control": { "key": "control", "value": { "key": "value" } }
                    },
                    "allocations": [
                      {
                        "key": "rollout",
                        "splits": [{ "variationKey": "control", "shards": [] }],
                        "doLog": false
                      }
                    ]
                  }
                }
              }
            }
          }
        JSON
      end

      it 'returns flag result details' do
        expect(result.value).to eq([1, 2, 3])
        expect(result.reason).to eq('hardcoded')
      end
    end
  end
end
