# frozen_string_literal: true

# This spec validates our InternalEvaluator implementation against comprehensive
# test cases from the reference implementation, ensuring behavioral compatibility.
# 
# The test data comes from the same JSON files used by reference implementations
# across multiple languages, ensuring we maintain compatibility for eventual 
# binding replacement with libdatadog.

require_relative '../../../../lib/datadog/open_feature/binding/internal_evaluator'
require 'json'

RSpec.describe 'InternalEvaluator Test Cases' do
  # Path to test data used by reference implementations
  TEST_DATA_PATH = File.expand_path('../../../fixtures/ufc', __dir__)

  let(:evaluator) { create_evaluator }

  def create_evaluator
    # Load the flags-v1.json used by reference implementation tests
    flags_file = File.join(TEST_DATA_PATH, 'flags-v1.json')
    return nil unless File.exist?(flags_file)

    flags_config = JSON.parse(File.read(flags_file))
    
    # Extract the nested flags structure
    ufc_json = if flags_config.dig('data', 'attributes', 'flags')
      { 'flags' => flags_config.dig('data', 'attributes', 'flags') }
    else
      flags_config
    end
    
    Datadog::OpenFeature::Binding::InternalEvaluator.new(ufc_json.to_json)
  end

  def map_variation_type_to_symbol(variation_type)
    case variation_type
    when 'BOOLEAN' then :boolean
    when 'STRING' then :string
    when 'INTEGER' then :integer
    when 'NUMERIC' then :number
    when 'JSON' then :object
    else :string
    end
  end

  def format_evaluation_context(targeting_key, attributes)
    context = { 'targeting_key' => targeting_key }
    context.merge!(attributes || {})
  end

  def validate_result(expected, actual, context_info)
    # Validate main value
    expect(actual.value).to eq(expected['value']), 
      "Value mismatch for #{context_info}: expected #{expected['value']}, got #{actual.value}"

    # Validate variant if expected (some tests only check value for error cases)
    if expected['variant']
      expect(actual.variant).to eq(expected['variant']), 
        "Variant mismatch for #{context_info}: expected #{expected['variant']}, got #{actual.variant}"
    end

    # Validate flag metadata if expected
    if expected['flagMetadata']
      expect(actual.flag_metadata).to be_present, 
        "Expected flagMetadata to be present for #{context_info}"

      expected_meta = expected['flagMetadata']
      actual_meta = actual.flag_metadata

      # Validate all fields in flagMetadata
      expected_meta.each do |field, expected_value|
        expect(actual_meta[field]).to eq(expected_value), 
          "FlagMetadata field '#{field}' mismatch for #{context_info}: expected #{expected_value}, got #{actual_meta[field]}"
      end

      # Ensure no unexpected fields are present in actual result
      unexpected_fields = actual_meta.keys - expected_meta.keys
      expect(unexpected_fields).to be_empty, 
        "Unexpected flagMetadata fields for #{context_info}: #{unexpected_fields}"
    end
  end

  # Skip tests if test data is not available (e.g., in CI environments)
  before(:all) do
    skip "Test data not available at #{TEST_DATA_PATH}" unless Dir.exist?(TEST_DATA_PATH)
  end

  # Generate test cases for each JSON test file
  test_files = if Dir.exist?("#{TEST_DATA_PATH}/test_cases")
    Dir.glob("#{TEST_DATA_PATH}/test_cases/*.json").map { |f| File.basename(f) }.sort
  else
    []
  end

  test_files.each do |test_filename|
    describe "Test cases from #{test_filename}" do
      let(:test_cases) do
        test_file_path = File.join(TEST_DATA_PATH, 'test_cases', test_filename)
        JSON.parse(File.read(test_file_path))
      end

      # Create individual test cases for better granular reporting
      test_file_path = File.join(TEST_DATA_PATH, 'test_cases', test_filename)
      next unless File.exist?(test_file_path)
      
      test_cases_data = JSON.parse(File.read(test_file_path))
      
      test_cases_data.each_with_index do |test_case, index|
        context "Test case ##{index + 1}: #{test_case['targetingKey']}" do
          let(:test_case_data) { test_case }

          it "produces the expected evaluation result" do
            skip "Evaluator not available (test data missing)" unless evaluator

            flag_key = test_case_data['flag']
            variation_type = test_case_data['variationType']
            default_value = test_case_data['defaultValue']
            targeting_key = test_case_data['targetingKey']
            attributes = test_case_data['attributes']
            expected_result = test_case_data['result']

            # Execute evaluation (matches Rust test flow)
            expected_type = map_variation_type_to_symbol(variation_type)
            evaluation_context = format_evaluation_context(targeting_key, attributes)

            result = evaluator.get_assignment(
              flag_key, 
              evaluation_context, 
              expected_type, 
              Time.now, 
              default_value
            )

            # Validate against expected results
            context_info = "#{test_filename}##{index + 1}(#{targeting_key})"
            
            # Debug output for null-operator cases
            if test_filename.include?('null-operator')
              puts "\nDEBUG #{context_info}:"
              puts "  Result class: #{result.class}"
              puts "  Result: #{result.inspect}"
              puts "  Flag metadata: #{result.flag_metadata.inspect}"
              puts "  Flag metadata nil?: #{result.flag_metadata.nil?}"
              puts "  Flag metadata present?: #{result.flag_metadata ? 'YES' : 'NO'}"
            end
            
            validate_result(expected_result, result, context_info)
          end
        end
      end
    end
  end

  # Overall compatibility validation
  describe 'Reference implementation compatibility metrics' do
    it 'maintains high compatibility with reference implementation' do
      skip "Test data not available" unless evaluator && !test_files.empty?

      total_tests = 0
      passed_tests = 0
      failed_tests = []

      test_files.each do |test_filename|
        test_file_path = File.join(TEST_DATA_PATH, 'test_cases', test_filename)
        test_cases = JSON.parse(File.read(test_file_path))

        test_cases.each_with_index do |test_case, index|
          total_tests += 1
          test_name = "#{test_filename}##{index + 1}(#{test_case['targetingKey']})"

          begin
            flag_key = test_case['flag']
            variation_type = test_case['variationType']
            default_value = test_case['defaultValue']
            targeting_key = test_case['targetingKey']
            attributes = test_case['attributes']
            expected_result = test_case['result']

            expected_type = map_variation_type_to_symbol(variation_type)
            evaluation_context = format_evaluation_context(targeting_key, attributes)

            result = evaluator.get_assignment(flag_key, evaluation_context, expected_type, Time.now, default_value)

            # Check if test passes (all conditions must match)
            value_matches = result.value == expected_result['value']
            variant_matches = expected_result['variant'].nil? || result.variant == expected_result['variant']
            
            metadata_matches = true
            if expected_result['flagMetadata']
              if result.flag_metadata
                expected_meta = expected_result['flagMetadata']
                actual_meta = result.flag_metadata
                # Check all expected fields match and no unexpected fields exist
                metadata_matches = expected_meta.all? { |field, expected_value| 
                  actual_meta[field] == expected_value 
                } && (actual_meta.keys - expected_meta.keys).empty?
              else
                metadata_matches = false
              end
            end

            if value_matches && variant_matches && metadata_matches
              passed_tests += 1
            else
              failed_tests << {
                name: test_name,
                expected: expected_result,
                actual: {
                  value: result.value,
                  variant: result.variant,
                  metadata: result.flag_metadata
                }
              }
            end
          rescue => e
            failed_tests << {
              name: test_name,
              error: e.message
            }
          end
        end
      end

      success_rate = (passed_tests.to_f / total_tests * 100).round(1)

      # Report results
      puts "\n" + "="*60
      puts "RUST COMPATIBILITY REPORT"
      puts "="*60
      puts "Total test cases: #{total_tests}"
      puts "Passed: #{passed_tests} (#{success_rate}%)"
      puts "Failed: #{failed_tests.length}"

      # Show details for failed tests (helpful for debugging)
      if failed_tests.any?
        puts "\nFailed test cases:"
        failed_tests.first(5).each do |failure| # Show first 5 failures
          puts "  • #{failure[:name]}"
          if failure[:error]
            puts "    Error: #{failure[:error]}"
          else
            puts "    Expected: #{failure[:expected]['value']} (#{failure[:expected]['variant']})"
            puts "    Actual: #{failure[:actual][:value]} (#{failure[:actual][:variant]})"
          end
        end
        puts "    ... (#{failed_tests.length - 5} more)" if failed_tests.length > 5
      end

      # We expect very high compatibility (95%+) for production readiness
      # The reference implementation achieves 100%, we should be very close
      expect(success_rate).to be >= 95.0, 
        "Expected at least 95% compatibility with reference implementation, got #{success_rate}%. " \
        "This indicates potential behavioral differences that need investigation."

      # Ideally we should be at 98%+ for production confidence
      if success_rate >= 98.0
        puts "\n🎉 EXCELLENT: Ruby implementation is highly compatible with reference implementation!"
      elsif success_rate >= 95.0
        puts "\n✅ GOOD: Ruby implementation has strong compatibility with reference implementation."
      end
    end
  end

  # Test specific known compatibility fixes
  describe 'Specific compatibility validations' do
    it 'correctly handles MD5 sharding with salt separator' do
      skip "Evaluator not available" unless evaluator

      # This test validates the critical MD5 separator fix
      # The targeting key "charlie" should map to variant "two" (shard value >= 5000)
      context = { 'targeting_key' => 'charlie' }
      result = evaluator.get_assignment('integer-flag', context, :integer, Time.now, 0)
      
      expect(result.value).to eq(2), "Expected charlie to get variant 'two' (value 2) due to MD5 sharding"
      expect(result.variant).to eq('two'), "Expected variant 'two' for charlie"
    end

    it 'handles boolean rule evaluation correctly' do
      skip "Evaluator not available" unless evaluator

      # Test boolean ONE_OF matching
      context = { 'targeting_key' => 'alice', 'one_of_flag' => true }
      result = evaluator.get_assignment('boolean-one-of-matches', context, :integer, Time.now, 0)
      
      expect(result.value).to eq(1), "Expected boolean true to match ONE_OF condition"
    end

    it 'properly handles disabled flags' do
      skip "Evaluator not available" unless evaluator

      context = { 'targeting_key' => 'alice' }
      result = evaluator.get_assignment('disabled_flag', context, :integer, Time.now, 42)
      
      expect(result.value).to eq(42), "Expected default value for disabled flag"
      expect(result.error_code).to eq('FLAG_DISABLED'), "Expected FLAG_DISABLED error"
    end

    it 'returns appropriate errors for missing flags' do
      skip "Evaluator not available" unless evaluator

      context = { 'targeting_key' => 'alice' }
      result = evaluator.get_assignment('nonexistent-flag', context, :string, Time.now, 'default')
      
      expect(result.value).to eq('default'), "Expected default value for missing flag"
      expect(result.error_code).to eq('FLAG_UNRECOGNIZED_OR_DISABLED'), "Expected FLAG_UNRECOGNIZED_OR_DISABLED error"
    end
  end
end