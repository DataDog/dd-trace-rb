# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/evaluator'

RSpec.describe Datadog::OpenFeature::Evaluator do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:evaluator) { described_class.new(telemetry) }
  let(:logger) { instance_double(Datadog::Core::Logger) }
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
                "key": "test",
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

  before { allow(Datadog).to receive(:logger).and_return(logger) }

  describe '#fetch_value' do
    let(:result) { evaluator.fetch_value(flag_key: 'test', expected_type: :string) }

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

        allow(telemetry).to receive(:report)
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

    context 'when binding evaluator returns resolution details' do
      before do
        evaluator.ufc_json = ufc
        evaluator.reconfigure!
      end

      let(:result) { evaluator.fetch_value(flag_key: 'test', expected_type: :string) }

      it { expect(result.value).to eq('hello') }
    end
  end

  describe '#reconfigure!' do
    context 'when binding initialization fails with exception' do
      before do
        evaluator.ufc_json = ufc
        evaluator.reconfigure!

        allow(described_class::Binding::Evaluator).to receive(:new).and_raise(error)
      end

      let(:error) { StandardError.new('Ooops') }

      it 'reports error to telemetry and logs it' do
        expect(logger).to receive(:error).with(/Ooops/)
        expect(telemetry).to receive(:report)
          .with(error, description: match(/OpenFeature failed to reconfigure/))

        evaluator.ufc_json = '{}'
        expect { evaluator.reconfigure! }.not_to raise_error
      end

      it 'persists previouly configured evaluator' do
        allow(logger).to receive(:error)
        allow(telemetry).to receive(:report)

        evaluator.ufc_json = '{}'
        expect { evaluator.reconfigure! }.not_to change {
          evaluator.fetch_value(flag_key: 'test', expected_type: :string).value
        }.from('hello')
      end
    end

    context 'when binding initialization succeeds' do
      before do
        evaluator.ufc_json = ufc
        evaluator.reconfigure!
      end

      let(:new_ufc) do
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
                    "key": "test",
                    "enabled": true,
                    "variationType": "STRING",
                    "variations": {
                      "control": { "key": "control", "value": "goodbye" }
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

      xit 'reconfigures binding evaluator with new flags configuration' do
        expect { evaluator.ufc_json = new_ufc; evaluator.reconfigure!}
          .to change { evaluator.fetch_value(flag_key: 'test', expected_type: :string).value }
          .from('hello').to('goodbye')
      end
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
