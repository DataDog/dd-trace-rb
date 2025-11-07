# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'datadog/open_feature/binding/native_evaluator'

RSpec.describe Datadog::OpenFeature::Binding::NativeEvaluator do
  let(:sample_config_json) do
    {
      "id": "1",
      "createdAt": "2024-04-17T19:40:53.716Z",
      "format": "SERVER",
      "environment": {
        "name": "test"
      },
      "flags": {
        "test_flag": {
          "key": "test_flag",
          "enabled": true,
          "variationType": "STRING",
          "variations": {
            "control": {
              "key": "control",
              "value": "control_value"
            }
          },
          "allocations": [
            {
              "key": "rollout",
              "splits": [
                {
                  "variationKey": "control",
                  "shards": []
                }
              ],
              "doLog": false
            }
          ]
        }
      }
    }.to_json
  end

  before do
    # Skip tests if native support is not available
    skip 'Native FFE support not available' unless Datadog::OpenFeature::Binding::NativeEvaluator.supported?
  end

  describe '#initialize' do
    context 'with valid configuration JSON' do
      it 'initializes successfully with native configuration' do
        expect { described_class.new(sample_config_json) }.not_to raise_error
      end
    end

    context 'with invalid configuration JSON' do
      it 'raises ArgumentError with wrapped native error' do
        expect { described_class.new('invalid json') }.to raise_error(
          ArgumentError, 
          /Failed to initialize native FFE configuration/
        )
      end
    end
  end

  describe '#get_assignment' do
    let(:evaluator) { described_class.new(sample_config_json) }
    let(:context) { Datadog::OpenFeature::Binding::EvaluationContext.new('test_user') }

    context 'with existing flag' do
      it 'returns a ResolutionDetails object' do
        result = evaluator.get_assignment('test_flag', context)
        expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
      end

      it 'returns the correct flag value' do
        result = evaluator.get_assignment('test_flag', context)
        expect(result.value).to eq('control_value')
      end

      it 'has valid assignment metadata' do
        result = evaluator.get_assignment('test_flag', context)
        expect(result.reason).to be_a(Symbol)
        expect(result.error_code).to be_nil
        expect(result.error_message).to be_nil
      end
    end

    context 'with non-existing flag' do
      it 'returns a ResolutionDetails object with error information' do
        result = evaluator.get_assignment('nonexistent_flag', context)
        expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
        expect(result.reason).to eq(:error)
        expect(result.error_code).to eq(:flag_not_found)
      end
    end

    context 'with invalid flag key type' do
      it 'raises a TypeError' do
        expect { evaluator.get_assignment(123, context) }.to raise_error(TypeError)
      end
    end

    context 'with nil flag key' do
      it 'raises a TypeError' do
        expect { evaluator.get_assignment(nil, context) }.to raise_error(TypeError)
      end
    end
  end

  describe '.supported?' do
    it 'detects native FFE support availability' do
      result = described_class.supported?
      expect([true, false]).to include(result)
    end
  end

  describe 'native configuration integration' do
    it 'creates configuration in native mode' do
      evaluator = described_class.new(sample_config_json)
      config = evaluator.send(:configuration)
      expect(config.native_mode?).to be true
    end

    it 'creates evaluation context in native mode' do
      context = Datadog::OpenFeature::Binding::EvaluationContext.new('test_user', {'country' => 'US'})
      expect(context.native_mode?).to be true
    end
  end

  describe 'error handling' do
    let(:evaluator) { described_class.new(sample_config_json) }
    let(:context) { Datadog::OpenFeature::Binding::EvaluationContext.new('test_user') }

    context 'when native evaluation fails' do
      before do
        allow(Datadog::OpenFeature::Binding).to receive(:_native_get_assignment).and_raise('Native error')
      end

      it 'wraps native errors with descriptive messages' do
        expect { evaluator.get_assignment('test_flag', context) }.to raise_error(
          RuntimeError, 
          /Failed to evaluate flag 'test_flag' with native evaluator/
        )
      end
    end
  end

  describe 'integration test' do
    it 'performs a complete native flag evaluation workflow' do
      # Create native evaluator
      evaluator = described_class.new(sample_config_json)
      expect(evaluator).to be_a(described_class)

      # Create native evaluation context
      context = Datadog::OpenFeature::Binding::EvaluationContext.new('test_user')
      expect(context).to be_a(Datadog::OpenFeature::Binding::EvaluationContext)
      expect(context.native_mode?).to be true

      # Evaluate flag using native methods
      result = evaluator.get_assignment('test_flag', context)
      expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
      expect(result.value).to eq('control_value')
    end

    it 'works with evaluation context created with attributes' do
      evaluator = described_class.new(sample_config_json)
      context = Datadog::OpenFeature::Binding::EvaluationContext.new('test_user', {'plan' => 'premium'})
      
      result = evaluator.get_assignment('test_flag', context)
      expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
    end
  end
end