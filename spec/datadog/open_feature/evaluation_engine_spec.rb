# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/evaluation_engine'

RSpec.describe Datadog::OpenFeature::EvaluationEngine do
  let(:engine) { described_class.new(reporter, telemetry: telemetry, logger: logger) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
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

  describe '#fetch_value' do
    let(:result) { engine.fetch_value(flag_key: 'test', expected_type: :string) }

    context 'when binding evaluator is not ready' do
      it 'returns evaluation error and reports exposure' do
        expect(reporter).to receive(:report).with(
          kind_of(Datadog::OpenFeature::Binding::ResolutionDetails), flag_key: 'test', context: nil
        )

        expect(result.error_code).to eq('PROVIDER_NOT_READY')
        expect(result.error_message).to eq('Waiting for universal flag configuration')
        expect(result.reason).to eq('INITIALIZING')
      end
    end

    context 'when binding evaluator returns error' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

        allow_any_instance_of(Datadog::OpenFeature::Binding::Evaluator).to receive(:get_assignment)
          .and_return(error)
      end

      let(:error) do
        Datadog::OpenFeature::Binding::ResolutionDetails.new(
          error_code: 'PROVIDER_FATAL',
          error_message: 'Ooops',
          reason: 'ERROR',
          flag_metadata: {},
          extra_logging: {},
          do_log: false
        )
      end

      it 'returns evaluation error and reports exposure' do
        expect(reporter).to receive(:report).with(error, flag_key: 'test', context: nil)

        expect(result.error_code).to eq('PROVIDER_FATAL')
        expect(result.error_message).to eq('Ooops')
        expect(result.reason).to eq('ERROR')
      end
    end

    context 'when binding evaluator raises error' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

        allow(telemetry).to receive(:report)
        allow_any_instance_of(Datadog::OpenFeature::Binding::Evaluator).to receive(:get_assignment)
          .and_raise(error)
      end

      let(:error) { RuntimeError.new("Crash") }

      it 'returns evaluation error and does not report exposure' do
        expect(reporter).not_to receive(:report)

        expect(result.error_code).to eq('PROVIDER_FATAL')
        expect(result.error_message).to eq('Crash')
        expect(result.reason).to eq('ERROR')
      end
    end

    context 'when expected type not in the allowed list' do
      before do
        engine.configuration = ufc
        engine.reconfigure!
      end

      let(:result) { engine.fetch_value(flag_key: 'test', expected_type: :whatever) }

      it 'returns evaluation error and does not report exposure' do
        expect(reporter).not_to receive(:report)

        expect(result.error_code).to eq('UNKNOWN_TYPE')
        expect(result.error_message).to start_with('unknown type :whatever, allowed types')
        expect(result.reason).to eq('ERROR')
      end
    end

    context 'when binding evaluator returns resolution details' do
      before do
        engine.configuration = ufc
        engine.reconfigure!
      end

      let(:evaluation_context) { instance_double('OpenFeature::SDK::EvaluationContext') }
      let(:result) { engine.fetch_value(flag_key: 'test', expected_type: :string, evaluation_context: evaluation_context) }

      it 'returns resolved value and reports exposure' do
        expect(reporter).to receive(:report)
          .with(kind_of(Datadog::OpenFeature::Binding::ResolutionDetails), flag_key: 'test', context: evaluation_context)

        expect(result.value).to eq('hello')
      end
    end
  end

  describe '#reconfigure!' do
    context 'when configuration is not yet present' do
      it 'does nothing and logs the issue' do
        expect(logger).to receive(:debug).with(/OpenFeature: Removing configuration/)

        engine.reconfigure!
      end
    end

    context 'when binding initialization fails with exception' do
      before do
        engine.configuration = ufc
        engine.reconfigure!

        allow(Datadog::OpenFeature::Binding::Evaluator).to receive(:new).and_raise(error)
      end

      let(:error) { StandardError.new('Ooops') }

      it 'reports error to telemetry and logs it' do
        expect(logger).to receive(:error).with(/Ooops/)
        expect(telemetry).to receive(:report)
          .with(error, description: match(/OpenFeature: Failed to reconfigure/))

        engine.configuration = '{}'
        expect { engine.reconfigure! }.to raise_error(error)
      end

      it 'persists previouly configured evaluator' do
        allow(logger).to receive(:error)
        allow(telemetry).to receive(:report)
        allow(reporter).to receive(:report)

        engine.configuration = '{}'

        expect { engine.reconfigure! }.to raise_error(error)
        expect(engine.fetch_value(flag_key: 'test', expected_type: :string).value).to eq('hello')
      end
    end

    context 'when binding initialization succeeds' do
      before do
        engine.configuration = ufc
        engine.reconfigure!
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
        engine.configuration = new_ufc

        expect { engine.reconfigure! }.to change { engine.fetch_value(flag_key: 'test', expected_type: :string).value }
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
