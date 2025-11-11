# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'datadog/open_feature/binding/internal_evaluator'

RSpec.describe Datadog::OpenFeature::Binding::InternalEvaluator do
  let(:flags_v1_path) { File.join(__dir__, '../../../fixtures/ufc/flags-v1.json') }
  let(:flags_v1_json) { JSON.parse(File.read(flags_v1_path)) }
  let(:valid_ufc_json) { flags_v1_json.to_json }

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
        expect(config.error_code).to eq(:parse_error)
      end

      it 'stores configuration missing error for empty JSON' do
        evaluator = described_class.new('')
        config = evaluator.instance_variable_get(:@parsed_config)
        
        expect(config).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
        expect(config.error_code).to eq(:provider_not_ready)
      end
    end
  end

  describe '#get_assignment' do
    let(:evaluator) { described_class.new(valid_ufc_json) }

    context 'when initialization failed' do
      let(:bad_evaluator) { described_class.new('invalid json') }

      it 'returns the initialization error' do
        result = bad_evaluator.get_assignment('any_flag', {}, :string)
        
        expect(result.error_code).to eq(:parse_error)
        expect(result.error_message).to eq('failed to parse configuration')
        expect(result.value).to be_nil
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to eq({})
      end
    end


    context 'with type validation' do
      it 'returns TYPE_MISMATCH when types do not match' do
        result = evaluator.get_assignment('numeric_flag', {}, :boolean)
        
        expect(result.error_code).to eq(:type_mismatch)
        expect(result.error_message).to eq('invalid flag type (expected: boolean, found: NUMERIC)')
        expect(result.value).to be_nil
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to eq({})
      end

      it 'succeeds when types match' do
        result = evaluator.get_assignment('numeric_flag', {}, :float)
        
        expect(result.error_code).to be_nil  # nil for successful allocation match
        expect(result.error_message).to eq('')  # Empty string for success cases
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect(result.flag_metadata).to include("allocation_key")
        expect([true, false]).to include(result.do_log)
      end

      it 'succeeds when expected_type is nil (no validation)' do
        result = evaluator.get_assignment('numeric_flag', {}, nil)
        
        expect(result.error_code).to be_nil  # nil for successful allocation match
        expect(result.error_message).to eq('')  # Empty string for success cases
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect(result.flag_metadata).to include("allocation_key")
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
      # Test all error types
      flag_not_found = evaluator.get_assignment('missing', {}, :string)
      expect(flag_not_found.error_code).to eq(:flag_not_found)
      expect(flag_not_found.value).to be_nil
      expect(flag_not_found.variant).to be_nil
      expect(flag_not_found.flag_metadata).to eq({})

      flag_disabled = evaluator.get_assignment('disabled_flag', {}, :integer)
      expect(flag_disabled.error_code).to eq(:ok)  # Disabled flags return :ok (matches Rust ErrorCode::Ok)
      expect(flag_disabled.error_message).to eq('')  # Empty string for Ok cases
      expect(flag_disabled.value).to be_nil
      expect(flag_disabled.variant).to be_nil
      expect(flag_disabled.flag_metadata).to eq({})

      type_mismatch = evaluator.get_assignment('numeric_flag', {}, :boolean)
      expect(type_mismatch.error_code).to eq(:type_mismatch)
      expect(type_mismatch.value).to be_nil
      expect(type_mismatch.variant).to be_nil
      expect(type_mismatch.flag_metadata).to eq({})
    end

    it 'provides descriptive error messages matching Rust format' do
      result = evaluator.get_assignment('missing_flag', {}, :string)
      expect(result.error_message).to eq('flag is missing in configuration, it is either unrecognized or disabled')
      expect(result.value).to be_nil
      expect(result.variant).to be_nil
      expect(result.flag_metadata).to eq({})
      
      type_result = evaluator.get_assignment('numeric_flag', {}, :boolean)
      expect(type_result.error_message).to match(/invalid flag type \(expected: .*, found: .*\)/)
      expect(type_result.value).to be_nil
      expect(type_result.variant).to be_nil
      expect(type_result.flag_metadata).to eq({})
    end
  end

  describe 'UFC test case coverage' do
    let(:evaluator) { described_class.new(valid_ufc_json) }
    
    # Load all test case files from UFC reference implementation
    Dir.glob(File.join(__dir__, '../../../fixtures/ufc/test_cases/*.json')).each do |test_file|
      describe "Test cases from #{File.basename(test_file)}" do
        let(:test_cases) { JSON.parse(File.read(test_file)) }
        
        it 'executes all test cases in the file' do
          test_cases.each_with_index do |test_case, index|
            # Extract test case data
            flag_key = test_case['flag']
            variation_type = test_case['variationType'] 
            targeting_key = test_case['targetingKey']
            attributes = test_case['attributes'] || {}
            expected_result = test_case['result']
            
            # Convert variation type to expected_type symbol
            expected_type = case variation_type
                           when 'STRING' then :string
                           when 'INTEGER' then :integer
                           when 'NUMERIC' then :number
                           when 'BOOLEAN' then :boolean
                           when 'JSON' then :object
                           else nil
                           end
            
            # Build evaluation context - convert to OpenFeature SDK format (snake_case keys)
            evaluation_context = attributes.dup
            evaluation_context['targeting_key'] = targeting_key if targeting_key  # Convert camelCase to snake_case
            
            # Execute test case
            result = evaluator.get_assignment(flag_key, evaluation_context, expected_type)
            
            # Wrap expectations in aggregate_failures for better error reporting
            aggregate_failures "Test case ##{index + 1}: #{targeting_key} with #{attributes.keys.join(', ')}" do
              # Our internal evaluator returns nil for error cases (disabled flags, missing flags, etc.)
              # The provider layer handles returning default values
              # Only successful evaluations with variant + flagMetadata return actual values
              
              if expected_result.key?('variant') && expected_result.key?('flagMetadata')
                # Successful evaluation case
                expect(result.value).to eq(expected_result['value']), 
                  "Expected value #{expected_result['value'].inspect}, got #{result.value.inspect}"
                expect(result.variant).to eq(expected_result['variant']),
                  "Expected variant #{expected_result['variant'].inspect}, got #{result.variant.inspect}"
                expect(result.error_code).to be_nil,
                  "Expected nil error code for successful evaluation, got #{result.error_code.inspect}"
                  
                # Validate flag metadata
                expected_metadata = expected_result['flagMetadata']
                expect(result.flag_metadata).not_to be_nil,
                  "Expected flag metadata, got nil"
                expect(result.flag_metadata['allocation_key']).to eq(expected_metadata['allocationKey']),
                  "Expected allocation key #{expected_metadata['allocationKey'].inspect}, got #{result.flag_metadata&.[]('allocation_key').inspect}"
                expect(result.flag_metadata['variation_type']).to eq(expected_metadata['variationType']),
                  "Expected variation type #{expected_metadata['variationType'].inspect}, got #{result.flag_metadata&.[]('variation_type').inspect}"
                expect(result.flag_metadata['do_log']).to eq(expected_metadata['doLog']),
                  "Expected do_log #{expected_metadata['doLog'].inspect}, got #{result.flag_metadata&.[]('do_log').inspect}"
              else
                # Error case - internal evaluator returns nil, provider handles defaults
                expect(result.value).to be_nil,
                  "Expected nil value for error case (provider handles default values), got #{result.value.inspect}"
                expect(result.variant).to be_nil,
                  "Expected nil variant for error case, got #{result.variant.inspect}"
                expect(result.flag_metadata).to eq({}),
                  "Expected empty flag metadata for error case, got #{result.flag_metadata.inspect}"
                
                # Should have an appropriate error code
                expect([:ok, :flag_not_found, :type_mismatch, :parse_error, :provider_not_ready, :general]).to include(result.error_code),
                  "Expected valid error code for error case, got #{result.error_code.inspect}"
              end
            end
          end
        end
      end
    end
  end
end
