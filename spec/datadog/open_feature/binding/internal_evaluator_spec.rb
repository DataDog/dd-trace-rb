# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'datadog/open_feature/binding/internal_evaluator'

RSpec.describe Datadog::OpenFeature::Binding::InternalEvaluator do
  let(:flags_v1_path) { File.join(__dir__, '../../../fixtures/ufc/flags-v1.json') }
  let(:flags_v1_json) { JSON.parse(File.read(flags_v1_path)) }
  let(:ufc_attributes) { flags_v1_json['data']['attributes'] } # UFC = Universal Flag Configuration
  let(:valid_ufc_json) { ufc_attributes.to_json }

  describe '#initialize' do
    context 'with valid UFC JSON' do
      it 'parses configuration successfully' do
        evaluator = described_class.new(valid_ufc_json)
        config = evaluator.instance_variable_get(:@parsed_config)
        
        expect(config).to be_a(Datadog::OpenFeature::Binding::Configuration)
        expect(config.flags).not_to be_empty
      end
    end

    context 'with invalid UFC JSON' do
      it 'stores parse error for malformed JSON' do
        evaluator = described_class.new('invalid json')
        config = evaluator.instance_variable_get(:@parsed_config)
        
        expect(config).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
        expect(config.error_code).to eq(:ParseError)
      end

      it 'stores parse error for empty JSON' do
        evaluator = described_class.new('')
        config = evaluator.instance_variable_get(:@parsed_config)
        
        expect(config).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
        expect(config.error_code).to eq(:ParseError)
      end
    end
  end

  describe '#get_assignment' do
    let(:evaluator) { described_class.new(valid_ufc_json) }

    context 'when initialization failed' do
      let(:bad_evaluator) { described_class.new('invalid json') }

      it 'returns the initialization error with default value' do
        result = bad_evaluator.get_assignment('any_flag', {}, :string, 'my_default')
        
        expect(result.error_code).to eq(:ParseError)
        expect(result.error_message).to eq('failed to parse configuration')
        expect(result.value).to eq('my_default')
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to be_nil
      end
    end


    context 'with type validation' do
      it 'returns TYPE_MISMATCH when types do not match with default value' do
        result = evaluator.get_assignment('numeric_flag', {}, :boolean, true)
        
        expect(result.error_code).to eq(:TypeMismatch)
        expect(result.error_message).to eq('invalid flag type (expected: boolean, found: NUMERIC)')
        expect(result.value).to eq(true)
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to be_nil
      end

      it 'succeeds when types match' do
        result = evaluator.get_assignment('numeric_flag', {}, :float, 0.0)
        
        expect(result.error_code).to be_nil
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect([true, false]).to include(result.do_log)
      end

      it 'succeeds when expected_type is nil (no validation)' do
        result = evaluator.get_assignment('numeric_flag', {}, nil, 'default')
        
        expect(result.error_code).to be_nil
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect([true, false]).to include(result.do_log)
      end
    end


    context 'type mapping' do
      let(:type_checker) { evaluator }

      it 'maps Ruby types to UFC variation types correctly' do
        # Access the private method for testing
        expect(type_checker.send(:type_matches?, 'BOOLEAN', :boolean)).to be true
        expect(type_checker.send(:type_matches?, 'STRING', :string)).to be true
        expect(type_checker.send(:type_matches?, 'INTEGER', :integer)).to be true
        expect(type_checker.send(:type_matches?, 'NUMERIC', :number)).to be true
        expect(type_checker.send(:type_matches?, 'NUMERIC', :float)).to be true
        expect(type_checker.send(:type_matches?, 'JSON', :object)).to be true
        
        # Test mismatches
        expect(type_checker.send(:type_matches?, 'BOOLEAN', :string)).to be false
        expect(type_checker.send(:type_matches?, 'STRING', :integer)).to be false
      end
    end
  end

  describe 'integration with Configuration classes' do
    let(:evaluator) { described_class.new(valid_ufc_json) }

    it 'properly integrates with parsed Configuration object' do
      config = evaluator.instance_variable_get(:@parsed_config)
      
      expect(config).to be_a(Datadog::OpenFeature::Binding::Configuration)
      expect(config.flags).to be_a(Hash)
      expect(config.flags.values).to all(be_a(Datadog::OpenFeature::Binding::Flag))
    end

    it 'accesses flag properties correctly' do
      config = evaluator.instance_variable_get(:@parsed_config)
      flag = config.get_flag('empty_flag')
      
      expect(flag).not_to be_nil
      expect(flag.enabled).to be true
      expect(flag.variation_type).to eq('STRING')
    end
  end

  describe 'error message consistency' do
    let(:evaluator) { described_class.new(valid_ufc_json) }

    it 'uses consistent error codes matching Rust implementation' do
      # Test all error types with default values
      flag_not_found = evaluator.get_assignment('missing', {}, :string, 'default')
      expect(flag_not_found.error_code).to eq(:FlagNotFound)
      expect(flag_not_found.value).to eq('default')
      expect(flag_not_found.variant).to be_nil
      expect(flag_not_found.flag_metadata).to be_nil

      flag_disabled = evaluator.get_assignment('disabled_flag', {}, :integer, 42)
      expect(flag_disabled.error_code).to eq(:Ok)  # Special case - expected condition
      expect(flag_disabled.value).to eq(42)
      expect(flag_disabled.variant).to be_nil
      expect(flag_disabled.flag_metadata).to be_nil

      type_mismatch = evaluator.get_assignment('numeric_flag', {}, :boolean, true)
      expect(type_mismatch.error_code).to eq(:TypeMismatch)
      expect(type_mismatch.value).to eq(true)
      expect(type_mismatch.variant).to be_nil
      expect(type_mismatch.flag_metadata).to be_nil
    end

    it 'provides descriptive error messages matching Rust format' do
      result = evaluator.get_assignment('missing_flag', {}, :string, 'fallback')
      expect(result.error_message).to eq('flag is missing in configuration, it is either unrecognized or disabled')
      expect(result.value).to eq('fallback')
      expect(result.variant).to be_nil
      expect(result.flag_metadata).to be_nil
      
      type_result = evaluator.get_assignment('numeric_flag', {}, :boolean, false)
      expect(type_result.error_message).to match(/invalid flag type \(expected: .*, found: .*\)/)
      expect(type_result.value).to eq(false)
      expect(type_result.variant).to be_nil
      expect(type_result.flag_metadata).to be_nil
    end
  end

  describe 'test case coverage' do
    let(:evaluator) { described_class.new(valid_ufc_json) }
    
    # Load all test case files at evaluation time
    Dir.glob(File.join(__dir__, '../../../fixtures/ufc/test_cases/*.json')).each do |test_file|
      describe "Test cases from #{File.basename(test_file)}" do
        let(:test_cases) { JSON.parse(File.read(test_file)) }
        
        it 'executes all test cases in the file' do
          test_cases.each_with_index do |test_case, index|
            # Extract test case data
            flag_key = test_case['flag']
            variation_type = test_case['variationType'] 
            default_value = test_case['defaultValue']
            targeting_key = test_case['targetingKey']
            attributes = test_case['attributes'] || {}
            expected_result = test_case['result']
            
            # Convert variation type to expected_type symbol
            expected_type = case variation_type
                           when 'STRING' then :string
                           when 'INTEGER' then :integer
                           when 'NUMERIC' then :float
                           when 'BOOLEAN' then :boolean
                           when 'JSON' then :object
                           else nil
                           end
            
            # Build evaluation context
            evaluation_context = attributes.dup
            evaluation_context['targetingKey'] = targeting_key if targeting_key
            
            # Execute test case
            result = evaluator.get_assignment(flag_key, evaluation_context, expected_type, default_value)
            
            # Wrap expectations in aggregate_failures for better error reporting
            aggregate_failures "Test case ##{index + 1}: #{targeting_key} with #{attributes.keys.join(', ')}" do
              # Check value
              expect(result.value).to eq(expected_result['value']), 
                "Expected value #{expected_result['value'].inspect}, got #{result.value.inspect}"
              
              # Check variant (if expected)
              if expected_result.key?('variant')
                expect(result.variant).to eq(expected_result['variant']),
                  "Expected variant #{expected_result['variant'].inspect}, got #{result.variant.inspect}"
              else
                expect(result.variant).to be_nil,
                  "Expected no variant, got #{result.variant.inspect}"
              end
              
              # Check flag metadata (if expected)
              if expected_result.key?('flagMetadata')
                expected_metadata = expected_result['flagMetadata']
                expect(result.flag_metadata).not_to be_nil,
                  "Expected flag metadata, got nil"
                expect(result.flag_metadata.allocation_key).to eq(expected_metadata['allocationKey']),
                  "Expected allocation key #{expected_metadata['allocationKey'].inspect}, got #{result.flag_metadata&.allocation_key.inspect}"
                expect(result.flag_metadata.variation_type).to eq(expected_metadata['variationType']),
                  "Expected variation type #{expected_metadata['variationType'].inspect}, got #{result.flag_metadata&.variation_type.inspect}"
                expect(result.flag_metadata.do_log).to eq(expected_metadata['doLog']),
                  "Expected do_log #{expected_metadata['doLog'].inspect}, got #{result.flag_metadata&.do_log.inspect}"
              else
                expect(result.flag_metadata).to be_nil,
                  "Expected no flag metadata, got #{result.flag_metadata.inspect}"
              end
              
              # Check error code - should be :Ok for successful evaluations, or specific error for failures
              if expected_result.key?('variant') || expected_result.key?('flagMetadata')
                expect(result.error_code).to eq(:Ok),
                  "Expected :Ok error code for successful evaluation, got #{result.error_code.inspect}"
              else
                # For cases that return default value only, check if it's an expected condition
                expect([nil, :Ok]).to include(result.error_code),
                  "Expected nil or :Ok error code for default value case, got #{result.error_code.inspect}"
              end
            end
          end
        end
      end
    end
  end
end
