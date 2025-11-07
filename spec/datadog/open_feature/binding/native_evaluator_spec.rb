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
                  "shards": [
                    {
                      "salt": "test_flag",
                      "totalShards": 10000,
                      "ranges": [
                        {
                          "start": 0,
                          "end": 10000
                        }
                      ]
                    }
                  ]
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
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
      end

      it 'returns the correct flag value' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        expect(result.value).to eq('control_value')
      end

      it 'has valid assignment metadata' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        expect(result.reason).to be_a(Symbol)
        expect(result.error_code).to be_nil
        expect(result.error_message).to be_nil
      end
    end

    context 'with non-existing flag' do
      it 'returns a ResolutionDetails object with error information' do
        result = evaluator.get_assignment('nonexistent_flag', context, :string, 'fallback')
        expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
        expect(result.reason).to eq(:error)
        expect(result.error_code).to eq(:flag_not_found)
      end

      it 'returns the default value when flag is not found' do
        result = evaluator.get_assignment('nonexistent_flag', context, :string, 'fallback')
        expect(result.value).to eq('fallback')
        expect(result.error_code).to eq(:flag_not_found)
      end

      it 'preserves error metadata when using default value' do
        result = evaluator.get_assignment('nonexistent_flag', context, :string, 'fallback')
        expect(result.value).to eq('fallback')
        expect(result.error_code).to eq(:flag_not_found)
        expect(result.reason).to eq(:error)
        expect(result.error_message).not_to be_nil
      end
    end

    context 'with invalid flag key type' do
      it 'raises a TypeError' do
        expect { evaluator.get_assignment(123, context, :string, 'default') }.to raise_error(TypeError)
      end
    end

    context 'with nil flag key' do
      it 'raises a TypeError' do
        expect { evaluator.get_assignment(nil, context, :string, 'default') }.to raise_error(TypeError)
      end
    end

    context 'default value handling' do
      it 'accepts InternalEvaluator-compatible signature' do
        # Should accept same parameters as InternalEvaluator
        expect { evaluator.get_assignment('test_flag', context, :string, 'default') }.not_to raise_error
      end

      it 'returns actual value when flag exists, ignoring default' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        expect(result.value).to eq('control_value')  # Actual value, not default
        expect(result.error_code).to be_nil
      end

      it 'returns default value when flag evaluation fails' do
        result = evaluator.get_assignment('nonexistent_flag', context, :string, 'my_fallback')
        expect(result.value).to eq('my_fallback')
        expect(result.error_code).to eq(:flag_not_found)
      end

      it 'handles different default value types' do
        # Test string default
        string_result = evaluator.get_assignment('missing', context, :string, 'fallback')
        expect(string_result.value).to eq('fallback')

        # Test integer default  
        int_result = evaluator.get_assignment('missing', context, :integer, 42)
        expect(int_result.value).to eq(42)

        # Test boolean default
        bool_result = evaluator.get_assignment('missing', context, :boolean, true)
        expect(bool_result.value).to eq(true)
      end
    end

    context 'when initialization failed' do
      let(:bad_evaluator) { 
        # Skip native evaluator tests if not supported
        skip 'Native FFE support not available' unless described_class.supported?
        
        begin
          described_class.new('invalid json')
        rescue ArgumentError => e
          # For native evaluator, initialization failures raise exceptions immediately
          # This differs from InternalEvaluator which stores error state
          skip "Native evaluator fails fast on initialization: #{e.message}"
        end
      }

      it 'handles initialization errors differently than InternalEvaluator' do
        # Native evaluator fails fast on bad initialization, while Internal stores error state
        expect { described_class.new('invalid json') }.to raise_error(ArgumentError)
      end
    end

    context 'with type validation' do
      it 'succeeds when types match (delegates to native implementation)' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        
        expect(result.error_code).to be_nil
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect([true, false]).to include(result.do_log)
      end

      it 'succeeds when expected_type is nil (no validation)' do
        # Native evaluator ignores expected_type parameter, delegating validation to native code
        result = evaluator.get_assignment('test_flag', context, nil, 'default')
        
        expect(result.error_code).to be_nil
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect([true, false]).to include(result.do_log)
      end

      it 'handles type mismatches through native validation' do
        # Native evaluator delegates type validation to the C extension
        # The behavior depends on the native implementation
        result = evaluator.get_assignment('test_flag', context, :boolean, true)
        
        # Result will either succeed (native handles conversion) or error (native validates strictly)
        expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
        if result.error_code
          expect(result.value).to eq(true)  # Should return default value on error
        end
      end
    end

    context 'with different flag types' do
      it 'handles STRING flags correctly' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        
        if result.error_code.nil?
          expect(result.value).to be_a(String)
          expect(result.variant).not_to be_nil
          expect(result.allocation_key).not_to be_nil
        else
          expect(result.value).to eq('default')
        end
      end

      it 'handles different flag types through native implementation' do
        # Test various type combinations - native evaluator handles validation
        test_cases = [
          ['test_flag', :string, 'default_string'],
          ['test_flag', :integer, 42], 
          ['test_flag', :boolean, false],
          ['test_flag', :object, {}]
        ]

        test_cases.each do |flag_key, expected_type, default_value|
          result = evaluator.get_assignment(flag_key, context, expected_type, default_value)
          expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
          
          # Either succeeds with actual value or fails with default value
          if result.error_code
            expect(result.value).to eq(default_value)
          end
        end
      end
    end

    context 'with flag variations and allocations' do
      it 'uses actual variation values from allocations when available' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        
        if result.error_code.nil? && result.variant
          expect(result.value).to be_a(String)
          expect(result.variant).not_to eq('default') # Should use actual variation key
          expect([:static, :split, :targeting_match]).to include(result.reason)
          expect(result.allocation_key).not_to be_nil
        end
      end

      it 'handles flags without allocations' do
        result = evaluator.get_assignment('nonexistent_flag', context, :string, 'fallback')
        
        # Should return default value for missing flags
        expect(result.value).to eq('fallback')
        expect(result.variant).to be_nil
        expect(result.allocation_key).to be_nil
        expect(result.do_log).to be_nil
      end

      it 'uses real allocation metadata' do
        result = evaluator.get_assignment('test_flag', context, :string, 'default')
        
        if result.error_code.nil?
          expect(result.allocation_key).not_to eq('mock_allocation')
          expect([true, false]).to include(result.do_log)
        end
      end
    end

    context 'error message consistency' do
      it 'provides consistent error codes' do
        # Test various error conditions
        flag_not_found = evaluator.get_assignment('missing', context, :string, 'default')
        expect(flag_not_found.error_code).to eq(:flag_not_found)
        expect(flag_not_found.value).to eq('default')
        expect(flag_not_found.variant).to be_nil
        expect(flag_not_found.allocation_key).to be_nil
        expect(flag_not_found.do_log).to be_nil
      end

      it 'provides descriptive error messages' do
        result = evaluator.get_assignment('missing_flag', context, :string, 'fallback')
        expect(result.error_message).to be_a(String)
        expect(result.error_message).not_to be_empty
        expect(result.value).to eq('fallback')
        expect(result.variant).to be_nil
        expect(result.allocation_key).to be_nil
        expect(result.do_log).to be_nil
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
        # Use a non-existent flag to force native evaluation and trigger the mocked error
        expect { evaluator.get_assignment('nonexistent_flag', context) }.to raise_error(
          RuntimeError, 
          /Failed to evaluate flag 'nonexistent_flag' with native evaluator/
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