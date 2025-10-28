# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/evaluator'

RSpec.describe Datadog::OpenFeature::Evaluator do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:evaluator) { described_class.new(telemetry) }
  let(:ufc) do
    <<~JSON
      {
        "data": {
          "type": "universal-flag-configuration",
          "id": "1",
          "attributes": {
            "createdAt": "2024-04-17T19:40:53.716Z",
            "format": "SERVER",
            "environment": { "name": "test" },
            "flags": {
              "test_flag": {
                "key": "test_flag",
                "enabled": true,
                "variationType": "STRING",
                "variations": {
                  "control": { "key": "control", "value": "control_value" }
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

  before { allow(telemetry).to receive(:report) }

  describe '#fetch_value' do
    let(:result) { evaluator.fetch_value(flag_key: 'test', expected_type: :boolean) }

    context 'when binding evaluator is not ready' do
      it 'returns evaluation error' do
        expect(result.reason).to eq('INITIALIZING')
        expect(result.code).to eq('PROVIDER_NOT_READY')
        expect(result.message).to eq('Waiting for Universal Flag Configuration')
      end
    end

    context 'when binding evaluator returns error' do
      before do
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow_any_instance_of(described_class::Binding::Evaluator).to receive(:get_assignment)
          .and_return(error)
      end

      let(:error) { described_class::ResolutionError.new(reason: 'ERROR', code: 'PROVIDER_FATAL', message: 'Ooops') }

      it 'returns evaluation error' do
        expect(result.reason).to eq('ERROR')
        expect(result.code).to eq('PROVIDER_FATAL')
        expect(result.message).to eq('Ooops')
      end
    end

    context 'when binding evaluator raises error' do
      before do
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow_any_instance_of(described_class::Binding::Evaluator).to receive(:get_assignment)
          .and_raise(error)
      end

      let(:error) { RuntimeError.new("Crash") }

      it 'returns evaluation error' do
        expect(result.reason).to eq('ERROR')
        expect(result.code).to eq('PROVIDER_FATAL')
        expect(result.message).to eq('Crash')
      end
    end

    context 'when expected type not in the allowed list' do
      before do
        evaluator.ufc_json = ufc
        evaluator.reconfigure!
      end

      let(:result) { evaluator.fetch_value(flag_key: 'test', expected_type: :whatever) }

      it 'returns evaluation error' do
        expect(result.reason).to eq('ERROR')
        expect(result.code).to eq('UNKNOWN_TYPE')
        expect(result.message).to match(/unknown type :whatever, allowed types/)
      end
    end

    xcontext 'when binding evaluator returns resolution details' do
    end
  end

  xdescribe '#reconfigure' do
    context 'when binding initialization fails with exception' do
    end

    context 'when binding initialization succeeds' do
    end
  end

  xdescribe 'Evaluation logic' do
    describe 'boolean' do
    end

    describe 'string' do
    end

    describe 'number' do
    end

    describe 'object' do
    end
  end
end
