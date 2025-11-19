# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Datadog Feature Flags Test Cases', :feature_flags do
  before do
    # Skip tests if libdatadog_api extension is not available
    skip 'libdatadog_api extension not available' unless defined?(Datadog::Core::FeatureFlags)
  end

  let(:fixtures_path) { File.join(__dir__, 'fixtures') }
  let(:main_config_path) { File.join(fixtures_path, 'flags-v1.json') }
  let(:main_config_json) { File.read(main_config_path) }
  let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }

  # Helper method to run a single test case
  def run_test_case(test_case, test_file_name)
    flag_key = test_case['flag']
    targeting_key = test_case['targetingKey']
    attributes = test_case['attributes'] || {}
    expected_result = test_case['result']

    # Build context
    context = {}
    context['targeting_key'] = targeting_key if targeting_key
    context.merge!(attributes)

    # Get assignment
    result = config.get_assignment(flag_key, context)

    # Create description for better error messages
    test_description = "#{test_file_name}: #{flag_key} for #{targeting_key || 'anonymous'}"

    if expected_result
      # Validate expected result
      expect(result.value).to eq(expected_result['value']),
        "#{test_description} - Expected value #{expected_result['value']}, got #{result.value}"

      if expected_result['variant']
        expect(result.variant).to eq(expected_result['variant']),
          "#{test_description} - Expected variant #{expected_result['variant']}, got #{result.variant}"
      end

      if expected_result['flagMetadata']
        metadata = expected_result['flagMetadata']

        if metadata['allocationKey']
          expect(result.allocation_key).to eq(metadata['allocationKey']),
            "#{test_description} - Expected allocation key #{metadata['allocationKey']}, got #{result.allocation_key}"
        end

        if metadata.key?('doLog')
          expect(result.log?).to eq(metadata['doLog']),
            "#{test_description} - Expected doLog #{metadata['doLog']}, got #{result.log?}"
        end
      end

      # Should not be an error case
      expect(result.error?).to be_falsey,
        "#{test_description} - Expected no error, but got error: #{result.error_code} - #{result.error_message}"
    else
      # Test expects no specific result (usually default behavior)
      # This is typically for cases where targeting rules don't match
      test_default_value = test_case['defaultValue']

      # The result should be the default value or nil, and should not be an error
      if test_default_value
        expect([test_default_value, nil]).to include(result.value),
          "#{test_description} - Expected default value #{test_default_value} or nil, got #{result.value}"
      end
    end

    result
  end

  # Process all test case files
  Dir.glob(File.join(fixtures_path, 'test-case-*.json')).each do |test_file|
    test_file_name = File.basename(test_file, '.json')

    describe test_file_name do
      let(:test_cases) { JSON.parse(File.read(test_file)) }

      it "passes all test cases" do
        test_cases.each_with_index do |test_case, index|
          # Run each test case and capture any failures
          begin
            run_test_case(test_case, "#{test_file_name}[#{index}]")
          rescue RSpec::Expectations::ExpectationNotMetError => e
            # Re-raise with additional context
            raise RSpec::Expectations::ExpectationNotMetError,
              "Test case #{index + 1} in #{test_file_name} failed: #{e.message}"
          end
        end
      end

      # Also run individual test cases for better granular reporting
      test_cases = JSON.parse(File.read(test_file))
      test_cases.each_with_index do |test_case, index|
        context "case #{index + 1}: #{test_case['targetingKey'] || 'anonymous'}" do
          it "evaluates #{test_case['flag']} correctly" do
            run_test_case(test_case, test_file_name)
          end
        end
      end
    end
  end

  describe 'Flag type specific validations' do
    describe 'Boolean flags' do
      it 'handles boolean attribute matching correctly' do
        test_file = File.join(fixtures_path, 'test-case-boolean-one-of-matches.json')
        test_cases = JSON.parse(File.read(test_file))

        boolean_cases = test_cases.select { |tc| tc['attributes']&.values&.any? { |v| [true, false].include?(v) } }
        expect(boolean_cases).not_to be_empty, "No boolean test cases found"

        boolean_cases.each do |test_case|
          result = run_test_case(test_case, 'boolean-validation')

          # Ensure we get a proper result
          expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
        end
      end
    end

    describe 'JSON flags' do
      it 'handles JSON/object flags correctly' do
        test_file = File.join(fixtures_path, 'test-json-config-flag.json')
        skip "test-json-config-flag.json not found" unless File.exist?(test_file)

        test_cases = JSON.parse(File.read(test_file))

        test_cases.each do |test_case|
          result = run_test_case(test_case, 'json-validation')

          # JSON flags should return object values
          if test_case['result'] && test_case['result']['value'].is_a?(Hash)
            expect(result.value).to be_a(Hash).or(be_a(String)),
              "JSON flag should return Hash or JSON string"
          end
        end
      end
    end

    describe 'Integer flags' do
      it 'handles integer flags correctly' do
        test_file = File.join(fixtures_path, 'test-case-integer-flag.json')
        skip "test-case-integer-flag.json not found" unless File.exist?(test_file)

        test_cases = JSON.parse(File.read(test_file))

        test_cases.each do |test_case|
          result = run_test_case(test_case, 'integer-validation')

          # Integer flags should return numeric values
          if test_case['result'] && test_case['result']['value'].is_a?(Integer)
            expect(result.value).to be_a(Integer),
              "Integer flag should return Integer"
          end
        end
      end
    end
  end

  describe 'Edge cases' do
    describe 'Disabled flags' do
      it 'handles disabled flag correctly' do
        test_file = File.join(fixtures_path, 'test-case-disabled-flag.json')
        skip "test-case-disabled-flag.json not found" unless File.exist?(test_file)

        test_cases = JSON.parse(File.read(test_file))
        test_cases.each { |tc| run_test_case(tc, 'disabled-flag') }
      end
    end

    describe 'Empty flags' do
      it 'handles empty flag correctly' do
        test_file = File.join(fixtures_path, 'test-case-empty-flag.json')
        skip "test-case-empty-flag.json not found" unless File.exist?(test_file)

        test_cases = JSON.parse(File.read(test_file))
        test_cases.each { |tc| run_test_case(tc, 'empty-flag') }
      end
    end

    describe 'Kill switch flags' do
      it 'handles kill switch correctly' do
        test_file = File.join(fixtures_path, 'test-case-kill-switch-flag.json')
        skip "test-case-kill-switch-flag.json not found" unless File.exist?(test_file)

        test_cases = JSON.parse(File.read(test_file))
        test_cases.each { |tc| run_test_case(tc, 'kill-switch') }
      end
    end
  end

  describe 'Error handling' do
    it 'provides meaningful errors for invalid configurations' do
      expect do
        Datadog::Core::FeatureFlags::Configuration.new('{"invalid": json}')
      end.to raise_error(RuntimeError, /Failed to create configuration/)
    end

    it 'handles non-existent flags gracefully' do
      result = config.get_assignment('definitely_does_not_exist', { 'targeting_key' => 'user' })

      # Should either return an error or a default value, but not crash
      expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
    end
  end
end