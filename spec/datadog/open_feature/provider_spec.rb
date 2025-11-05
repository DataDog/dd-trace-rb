# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/provider'
require 'datadog/open_feature/evaluation_engine'

RSpec.describe Datadog::OpenFeature::Provider do
  before do
    allow(telemetry).to receive(:report)
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
  end

  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(reporter, telemetry: telemetry) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  subject(:provider) { described_class.new }

  describe '#fetch_boolean_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_boolean_value(flag_key: 'flag', default_value: false)

        expect(result.value).to eq(false)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when engine is configured' do
      before do
        engine.configuration = ufc
        engine.reconfigure!
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
        expect(result.reason).to eq('TARGETING_MATCH')
      end
    end
  end

  describe '#fetch_string_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_string_value(flag_key: 'flag', default_value: 'default')

        expect(result.value).to eq('default')
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when engine is configured' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

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
        expect(result.reason).to eq('TARGETING_MATCH')
      end
    end
  end

  describe '#fetch_number_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_number_value(flag_key: 'flag', default_value: 0)

        expect(result.value).to eq(0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when engine is configured' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

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
        expect(result.reason).to eq('TARGETING_MATCH')
      end
    end
  end

  describe '#fetch_integer_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_integer_value(flag_key: 'flag', default_value: 1)

        expect(result.value).to eq(1)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when engine is configured' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

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
        expect(result.reason).to eq('TARGETING_MATCH')
      end
    end
  end

  describe '#fetch_float_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_float_value(flag_key: 'flag', default_value: 0.0)

        expect(result.value).to eq(0.0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when engine is configured' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

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
        expect(result.reason).to eq('TARGETING_MATCH')
      end
    end
  end

  describe '#fetch_object_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_object_value(flag_key: 'flag', default_value: { 'default' => true })

        expect(result.value).to eq({ 'default' => true })
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when engine is configured' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

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
        expect(result.reason).to eq('TARGETING_MATCH')
      end
    end
  end
end
