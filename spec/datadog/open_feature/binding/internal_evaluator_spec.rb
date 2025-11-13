# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open_feature/sdk'
require 'datadog/open_feature/binding/internal_evaluator'

RSpec.describe Datadog::OpenFeature::Binding::InternalEvaluator do
  # The InternalEvaluator implements a three-case evaluation model:
  # Case 1: Successful evaluation with result - has variant and value
  # Case 2: No results (disabled/default) - not an error but no allocation matched
  # Case 3: Evaluation error - has error_code and error_message
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
        result = evaluator.get_assignment('any_flag', {}, 'string', 'test_default')

        expect(result.error_code).to eq('CONFIGURATION_PARSE_ERROR')
        expect(result.error_message).to eq('failed to parse configuration')
        expect(result.value).to eq('test_default')
        expect(result.variant).to be_nil
      end

      it 'stores configuration missing error for empty JSON' do
        evaluator = described_class.new('')
        result = evaluator.get_assignment('any_flag', {}, 'string', 'test_default')

        expect(result.error_code).to eq('CONFIGURATION_MISSING')
        expect(result.error_message).to eq('flags configuration is missing')
        expect(result.value).to eq('test_default')
        expect(result.variant).to be_nil
      end
    end
  end

  describe '#get_assignment' do
    let(:evaluator) { described_class.new(valid_ufc_json) }

    context 'when initialization failed' do
      let(:bad_evaluator) { described_class.new('invalid json') }

      it 'returns the initialization error' do
        result = bad_evaluator.get_assignment('any_flag', {}, 'string', 'test_default')

        expect(result.error_code).to eq('CONFIGURATION_PARSE_ERROR')
        expect(result.error_message).to eq('failed to parse configuration')
        expect(result.value).to eq('test_default')
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to eq({})
      end
    end

    context 'with type validation' do
      it 'returns TYPE_MISMATCH when types do not match' do
        result = evaluator.get_assignment('numeric_flag', {}, 'boolean', 'test_default')

        expect(result.error_code).to eq('TYPE_MISMATCH')
        expect(result.error_message).to eq('invalid flag type (expected: boolean, found: NUMERIC)')
        expect(result.value).to eq('test_default')
        expect(result.variant).to be_nil
        expect(result.flag_metadata).to eq({})
      end

      it 'succeeds when types match' do
        result = evaluator.get_assignment('numeric_flag', {}, 'float', 'test_default')

        expect(result.error_code).to be_nil  # nil for successful allocation match
        expect(result.error_message).to be_nil  # nil for successful cases
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect(result.flag_metadata).to include("allocationKey")
        expect([true, false]).to include(result.do_log)
      end

      it 'succeeds when expected_type is nil (no validation)' do
        result = evaluator.get_assignment('numeric_flag', {}, nil, 'test_default')

        expect(result.error_code).to be_nil  # nil for successful allocation match
        expect(result.error_message).to be_nil  # nil for successful cases
        expect(result.value).not_to be_nil
        expect(result.variant).not_to be_nil
        expect(result.allocation_key).not_to be_nil
        expect(result.flag_metadata).to include("allocationKey")
        expect([true, false]).to include(result.do_log)
      end
    end

    context 'type mapping' do
      let(:type_checker) { evaluator }

      it 'maps Ruby types to UFC variation types correctly' do
        # Access the private method for testing
        expect(type_checker.send(:type_matches?, 'BOOLEAN', 'boolean')).to be true
        expect(type_checker.send(:type_matches?, 'STRING', 'string')).to be true
        expect(type_checker.send(:type_matches?, 'INTEGER', 'integer')).to be true
        expect(type_checker.send(:type_matches?, 'NUMERIC', 'float')).to be true
        expect(type_checker.send(:type_matches?, 'NUMERIC', 'float')).to be true
        expect(type_checker.send(:type_matches?, 'JSON', 'object')).to be true

        # Test mismatches
        expect(type_checker.send(:type_matches?, 'BOOLEAN', 'string')).to be false
        expect(type_checker.send(:type_matches?, 'STRING', 'integer')).to be false
      end
    end

    context 'evaluation context types' do
      it 'accepts hash evaluation contexts including from OpenFeature SDK fields' do
        # Test with hash-based evaluation context
        hash_context = {'targeting_key' => 'user123', 'attr1' => 'value1'}
        hash_result = evaluator.get_assignment('numeric_flag', hash_context, 'float', 'test_default')

        expect(hash_result.error_code).to be_nil
        expect(hash_result.value).not_to be_nil
        expect(hash_result.variant).not_to be_nil

        # Test with hash extracted from OpenFeature SDK EvaluationContext.fields
        sdk_context = OpenFeature::SDK::EvaluationContext.new(
          targeting_key: 'user123',
          fields: {'attr1' => 'value1'}
        )

        sdk_result = evaluator.get_assignment('numeric_flag', sdk_context.fields, 'float', 'test_default')

        expect(sdk_result.error_code).to be_nil
        expect(sdk_result.value).not_to be_nil
        expect(sdk_result.variant).not_to be_nil

        # Both contexts should produce equivalent results for the same user
        expect(hash_result.variant).to eq(sdk_result.variant)
        expect(hash_result.value).to eq(sdk_result.value)
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
      flag_not_found = evaluator.get_assignment('missing', {}, 'string', 'test_default')
      expect(flag_not_found.error_code).to eq('FLAG_UNRECOGNIZED_OR_DISABLED')
      expect(flag_not_found.value).to eq('test_default')
      expect(flag_not_found.variant).to be_nil
      expect(flag_not_found.flag_metadata).to eq({})

      flag_disabled = evaluator.get_assignment('disabled_flag', {}, 'integer', 'test_default')
      expect(flag_disabled.error_code).to be_nil  # Disabled flags are successful cases with nil error_code
      expect(flag_disabled.error_message).to be_nil  # nil for successful disabled cases
      expect(flag_disabled.reason).to eq('DISABLED')  # Disabled reason
      expect(flag_disabled.value).to eq('test_default')
      expect(flag_disabled.variant).to be_nil
      expect(flag_disabled.flag_metadata).to eq({})

      type_mismatch = evaluator.get_assignment('numeric_flag', {}, 'boolean', 'test_default')
      expect(type_mismatch.error_code).to eq('TYPE_MISMATCH')
      expect(type_mismatch.value).to eq('test_default')
      expect(type_mismatch.variant).to be_nil
      expect(type_mismatch.flag_metadata).to eq({})
    end

    it 'provides descriptive error messages matching Rust format' do
      result = evaluator.get_assignment('missing_flag', {}, 'string', 'test_default')
      expect(result.error_message).to eq('flag is missing in configuration, it is either unrecognized or disabled')
      expect(result.value).to eq('test_default')
      expect(result.variant).to be_nil
      expect(result.flag_metadata).to eq({})

      type_result = evaluator.get_assignment('numeric_flag', {}, 'boolean', 'test_default')
      expect(type_result.error_message).to match(/invalid flag type \(expected: .*, found: .*\)/)
      expect(type_result.value).to eq('test_default')
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
            when 'STRING' then 'string'
            when 'INTEGER' then 'integer'
            when 'NUMERIC' then 'float'
            when 'BOOLEAN' then 'boolean'
            when 'JSON' then 'object'
            end

            # Build evaluation context - convert to OpenFeature SDK format (snake_case keys)
            evaluation_context = attributes.dup
            evaluation_context['targeting_key'] = targeting_key if targeting_key  # Convert camelCase to snake_case

            # Execute test case
            result = evaluator.get_assignment(flag_key, evaluation_context, expected_type, 'test_default')

            # Wrap expectations in aggregate_failures for better error reporting
            aggregate_failures "Test case ##{index + 1}: #{targeting_key} with #{attributes.keys.join(", ")}" do
              # Check if test case has detailed expected results (variant and flagMetadata)
              has_detailed_expectations = expected_result.key?('variant') && expected_result.key?('flagMetadata')

              if has_detailed_expectations
                # Successful evaluation with detailed expectations from test case
                expect(result.value).to eq(expected_result['value']),
                  "Expected value #{expected_result["value"].inspect}, got #{result.value.inspect}"
                expect(result.variant).to eq(expected_result['variant']),
                  "Expected variant #{expected_result["variant"].inspect}, got #{result.variant.inspect}"
                expect(result.error_code).to be_nil,
                  "Expected nil error code for successful evaluation, got #{result.error_code.inspect}"
                expect(result.error_message).to be_nil,
                  "Expected nil error message for successful evaluation, got #{result.error_message.inspect}"
                expect(['STATIC', 'TARGETING_MATCH', 'SPLIT']).to include(result.reason),
                  "Expected success reason (static/targeting_match/split), got #{result.reason.inspect}"

                # Validate specific flag metadata values from test case
                expected_flag_metadata = expected_result['flagMetadata']
                expect(result.flag_metadata['allocationKey']).to eq(expected_flag_metadata['allocationKey']),
                  "Expected allocationKey #{expected_flag_metadata["allocationKey"].inspect}, got #{result.flag_metadata["allocationKey"].inspect}"
                expect(result.flag_metadata['doLog']).to eq(expected_flag_metadata['doLog']),
                  "Expected doLog #{expected_flag_metadata["doLog"].inspect}, got #{result.flag_metadata["doLog"].inspect}"
                expect(result.allocation_key).to eq(expected_flag_metadata['allocationKey']),
                  "Expected allocation_key #{expected_flag_metadata["allocationKey"].inspect}, got #{result.allocation_key.inspect}"
                expect(result.do_log).to eq(expected_flag_metadata['doLog']),
                  "Expected do_log #{expected_flag_metadata["doLog"].inspect}, got #{result.do_log.inspect}"

              elsif result.error_code.nil? && !result.variant.nil?
                # Successful evaluation without detailed expectations (fallback to structural validation)
                expect(result.value).to eq(expected_result['value']),
                  "Expected value #{expected_result["value"].inspect}, got #{result.value.inspect}"
                expect(result.variant).not_to be_nil,
                  "Expected variant for successful evaluation, got #{result.variant.inspect}"
                expect(result.error_code).to be_nil,
                  "Expected nil error code for successful evaluation, got #{result.error_code.inspect}"
                expect(result.error_message).to be_nil,
                  "Expected nil error message for successful evaluation, got #{result.error_message.inspect}"
                expect(['STATIC', 'TARGETING_MATCH', 'SPLIT']).to include(result.reason),
                  "Expected success reason (static/targeting_match/split), got #{result.reason.inspect}"

                # Validate flag metadata structure exists
                expect(result.flag_metadata).not_to be_empty,
                  "Expected flag metadata for successful evaluation, got #{result.flag_metadata.inspect}"
                expect(result.flag_metadata).to have_key('allocationKey'),
                  "Expected allocationKey in flag metadata, got #{result.flag_metadata.inspect}"
                expect(result.flag_metadata).to have_key('doLog'),
                  "Expected doLog in flag metadata, got #{result.flag_metadata.inspect}"
                expect(result.allocation_key).not_to be_nil,
                  "Expected allocation_key for successful evaluation, got #{result.allocation_key.inspect}"
                expect([true, false]).to include(result.do_log),
                  "Expected boolean do_log value, got #{result.do_log.inspect}"

              elsif result.error_code.nil? && result.variant.nil?
                # No allocation matched (disabled flag or no matching rules) - internal evaluator returns nil
                expect(result.value).to eq('test_default'),
                  "Expected nil value for disabled/default case, got #{result.value.inspect}"
                expect(result.variant).to be_nil,
                  "Expected nil variant for disabled/default case, got #{result.variant.inspect}"
                expect(result.error_code).to be_nil,
                  "Expected nil error code for disabled/default case, got #{result.error_code.inspect}"
                expect(result.error_message).to be_nil,
                  "Expected nil error message for disabled/default case, got #{result.error_message.inspect}"
                expect(['DISABLED', 'DEFAULT']).to include(result.reason),
                  "Expected disabled or default reason, got #{result.reason.inspect}"
                expect(result.flag_metadata).to eq({}),
                  "Expected empty flag metadata for disabled/default case, got #{result.flag_metadata.inspect}"
                expect(result.allocation_key).to be_nil,
                  "Expected nil allocation_key for disabled/default case, got #{result.allocation_key.inspect}"
                expect(result.do_log).to eq(false),
                  "Expected false do_log for disabled/default case, got #{result.do_log.inspect}"

              else
                # Evaluation error occurred
                expect(result.value).to eq('test_default'),
                  "Expected nil value for error case, got #{result.value.inspect}"
                expect(result.variant).to be_nil,
                  "Expected nil variant for error case, got #{result.variant.inspect}"
                expect(result.error_code).not_to be_nil,
                  "Expected error code for error case, got #{result.error_code.inspect}"
                expect(result.error_message).not_to be_nil,
                  "Expected error message for error case, got #{result.error_message.inspect}"
                expect(result.reason).to eq('ERROR'),
                  "Expected ERROR reason for error case, got #{result.reason.inspect}"
                expect(result.flag_metadata).to eq({}),
                  "Expected empty flag metadata for error case, got #{result.flag_metadata.inspect}"
                expect(result.allocation_key).to be_nil,
                  "Expected nil allocation_key for error case, got #{result.allocation_key.inspect}"
                expect(result.do_log).to eq(false),
                  "Expected false do_log for error case, got #{result.do_log.inspect}"
              end
            end
          end
        end
      end
    end
  end
end
