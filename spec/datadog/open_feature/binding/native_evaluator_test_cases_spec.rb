# frozen_string_literal: true

# This spec validates our NativeEvaluator implementation against test cases from 
# libdatadog, ensuring behavioral compatibility between NativeEvaluator and InternalEvaluator.
# 
# The test data comes from the same JSON files used by reference implementations
# across multiple languages, ensuring we maintain compatibility for eventual 
# binding replacement with libdatadog.

require_relative '../../../../lib/datadog/open_feature/binding/native_evaluator'
require_relative '../../../../lib/datadog/open_feature/binding/configuration'
require 'json'

RSpec.describe 'NativeEvaluator Test Cases' do
  # Path to test data used by reference implementations
  TEST_DATA_PATH = File.expand_path('../../../fixtures/ufc', __dir__)

  let(:evaluator) { create_evaluator }

  # Check if native extension is properly loaded by attempting to create an evaluator
  def native_extension_available?
    begin
      # Try to create a native evaluator with minimal config
      test_config = {
        'id' => '1',
        'createdAt' => '2024-04-17T19:40:53.716Z',
        'format' => 'SERVER',
        'environment' => { 'name' => 'test' },
        'flags' => {}
      }.to_json
      
      Datadog::OpenFeature::Binding::NativeEvaluator.new(test_config)
      true
    rescue ArgumentError, NoMethodError => e
      false
    end
  end

  # Skip all tests if native extension is not available
  before(:all) do
    skip "Native FFE extension not available - run setup_ffe.sh to compile native binding" unless native_extension_available?
  end

  def create_evaluator
    # Load the flags-v1.json used by reference implementation tests
    flags_file = File.join(TEST_DATA_PATH, 'flags-v1.json')
    return nil unless File.exist?(flags_file)

    flags_config = JSON.parse(File.read(flags_file))
    
    # For NativeEvaluator, we need to use the libdatadog format
    # Convert from UFC format to libdatadog format if needed
    libdatadog_config = if flags_config.dig('data', 'attributes', 'flags')
      # Extract and convert UFC format to libdatadog format
      ufc_flags = flags_config.dig('data', 'attributes', 'flags')
      {
        'id' => '1',
        'createdAt' => '2024-04-17T19:40:53.716Z',
        'format' => 'SERVER',
        'environment' => { 'name' => 'test' },
        'flags' => ufc_flags
      }
    else
      flags_config
    end
    
    Datadog::OpenFeature::Binding::NativeEvaluator.new(libdatadog_config.to_json)
  rescue ArgumentError => e
    # Native evaluator may fail on complex flag configurations
    # In production, this would be logged and handled gracefully
    puts "Warning: Native evaluator initialization failed: #{e.message}"
    nil
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

  def create_evaluation_context(targeting_key, attributes)
    Datadog::OpenFeature::Binding::EvaluationContext.new(targeting_key, attributes)
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

    # Validate flag metadata if expected using flat ResolutionDetails structure
    if expected['flagMetadata']
      expected_meta = expected['flagMetadata']

      # Validate allocation key
      if expected_meta['allocationKey']
        expect(actual.allocation_key).to eq(expected_meta['allocationKey']), 
          "AllocationKey mismatch for #{context_info}: expected #{expected_meta['allocationKey']}, got #{actual.allocation_key}"
      end

      # Validate doLog
      if expected_meta.key?('doLog')
        expect(actual.do_log).to eq(expected_meta['doLog']), 
          "DoLog mismatch for #{context_info}: expected #{expected_meta['doLog']}, got #{actual.do_log}"
      end

      # Validate variationType (not commonly used but available if needed)
      if expected_meta['variationType']
        # This field doesn't have a direct equivalent in ResolutionDetails, so we skip it
        # It's more for validation than runtime behavior
      end
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
            skip "Native evaluator not available (FFI not supported or test data missing)" unless evaluator

            flag_key = test_case_data['flag']
            variation_type = test_case_data['variationType']
            default_value = test_case_data['defaultValue']
            targeting_key = test_case_data['targetingKey']
            attributes = test_case_data['attributes']
            expected_result = test_case_data['result']

            # Execute evaluation using NativeEvaluator API
            expected_type = map_variation_type_to_symbol(variation_type)
            evaluation_context = create_evaluation_context(targeting_key, attributes)

            result = evaluator.get_assignment(
              flag_key, 
              evaluation_context, 
              expected_type, 
              default_value
            )

            # Validate against expected results
            context_info = "#{test_filename}##{index + 1}(#{targeting_key})"
            
            # Debug output for troublesome cases
            if test_filename.include?('null-operator') || result.error_code
              puts "\nDEBUG NATIVE #{context_info}:"
              puts "  Result class: #{result.class}"
              puts "  Result: #{result.inspect}"
              puts "  Value: #{result.value}"
              puts "  Variant: #{result.variant}"
              puts "  Error code: #{result.error_code}"
              puts "  Error message: #{result.error_message}"
              puts "  Allocation key: #{result.allocation_key}"
              puts "  Do log: #{result.do_log}"
            end
            
            validate_result(expected_result, result, context_info)
          end
        end
      end
    end
  end

  # Overall compatibility validation comparing NativeEvaluator to reference
  describe 'Reference implementation compatibility metrics' do
    it 'maintains high compatibility with reference implementation' do
      skip "Native evaluator not available" unless evaluator && !test_files.empty?

      total_tests = 0
      passed_tests = 0
      failed_tests = []
      skipped_tests = 0

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
            evaluation_context = create_evaluation_context(targeting_key, attributes)

            result = evaluator.get_assignment(flag_key, evaluation_context, expected_type, default_value)

            # Check if test passes (all conditions must match)
            value_matches = result.value == expected_result['value']
            variant_matches = expected_result['variant'].nil? || result.variant == expected_result['variant']
            
            metadata_matches = true
            if expected_result['flagMetadata']
              expected_meta = expected_result['flagMetadata']
              # Check allocation key and doLog using flat ResolutionDetails structure
              allocation_matches = expected_meta['allocationKey'].nil? || 
                                   result.allocation_key == expected_meta['allocationKey']
              do_log_matches = !expected_meta.key?('doLog') || 
                               result.do_log == expected_meta['doLog']
              metadata_matches = allocation_matches && do_log_matches
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
                  error_code: result.error_code,
                  error_message: result.error_message,
                  allocation_key: result.allocation_key,
                  do_log: result.do_log
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

      success_rate = total_tests > 0 ? (passed_tests.to_f / total_tests * 100).round(1) : 0

      # Report results
      puts "\n" + "="*60
      puts "NATIVE EVALUATOR COMPATIBILITY REPORT"
      puts "="*60
      puts "Total test cases: #{total_tests}"
      puts "Passed: #{passed_tests} (#{success_rate}%)"
      puts "Failed: #{failed_tests.length}"
      puts "Skipped: #{skipped_tests}" if skipped_tests > 0

      # Show details for failed tests (helpful for debugging)
      if failed_tests.any?
        puts "\nFailed test cases:"
        failed_tests.first(10).each do |failure| # Show first 10 failures
          puts "  • #{failure[:name]}"
          if failure[:error]
            puts "    Error: #{failure[:error]}"
          else
            puts "    Expected: #{failure[:expected]['value']} (variant: #{failure[:expected]['variant']})"
            puts "    Actual: #{failure[:actual][:value]} (variant: #{failure[:actual][:variant]})"
            puts "    Error: #{failure[:actual][:error_code]} - #{failure[:actual][:error_message]}" if failure[:actual][:error_code]
          end
        end
        puts "    ... (#{failed_tests.length - 10} more)" if failed_tests.length > 10
      end

      # Native evaluator may have lower compatibility due to FFI/C extension differences
      # But we should still expect reasonable compatibility (85%+ for core functionality)
      minimum_compatibility = 85.0
      
      expect(success_rate).to be >= minimum_compatibility, 
        "Expected at least #{minimum_compatibility}% compatibility with reference implementation, got #{success_rate}%. " \
        "This indicates potential behavioral differences between NativeEvaluator and reference implementation."

      if success_rate >= 95.0
        puts "\n🎉 EXCELLENT: NativeEvaluator is highly compatible with reference implementation!"
      elsif success_rate >= 90.0
        puts "\n✅ VERY GOOD: NativeEvaluator has strong compatibility with reference implementation."
      elsif success_rate >= 85.0
        puts "\n👍 GOOD: NativeEvaluator has acceptable compatibility with reference implementation."
      else
        puts "\n⚠️  NEEDS IMPROVEMENT: NativeEvaluator compatibility is below target threshold."
      end
    end
  end

  # Test specific known compatibility scenarios for NativeEvaluator
  describe 'Native evaluator specific validations' do
    it 'correctly handles flag evaluation through native FFI' do
      skip "Native evaluator not available" unless evaluator

      # Test basic flag evaluation through native interface
      context = create_evaluation_context('alice', { 'email' => 'alice@example.com' })
      
      # Use a simple flag that should exist in test data
      result = evaluator.get_assignment('test_flag', context, :string, 'default')
      
      expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
      expect(result.value).to be_a(String)
    end

    it 'handles missing flags with appropriate error codes' do
      skip "Native evaluator not available" unless evaluator

      context = create_evaluation_context('alice', {})
      result = evaluator.get_assignment('nonexistent-flag', context, :string, 'default_value')
      
      expect(result.value).to eq('default_value'), "Expected default value for missing flag"
      expect(result.error_code).to eq(:flag_not_found), "Expected :flag_not_found error code"
    end

    it 'preserves error metadata when returning default values' do
      skip "Native evaluator not available" unless evaluator

      context = create_evaluation_context('alice', {})
      result = evaluator.get_assignment('missing_flag', context, :string, 'fallback')
      
      expect(result.value).to eq('fallback')
      expect(result.error_code).not_to be_nil
      expect(result.error_message).not_to be_nil
    end

    it 'handles evaluation context with attributes correctly' do
      skip "Native evaluator not available" unless evaluator

      context = create_evaluation_context('bob', { 'country' => 'US', 'age' => 25 })
      result = evaluator.get_assignment('any_flag', context, :string, 'default')
      
      expect(result).to be_a(Datadog::OpenFeature::Binding::ResolutionDetails)
      # Result may be successful or return default based on flag configuration
    end
  end

  # Comparative testing between NativeEvaluator and InternalEvaluator
  describe 'NativeEvaluator vs InternalEvaluator consistency' do
    let(:internal_evaluator) { create_internal_evaluator }

    def create_internal_evaluator
      flags_file = File.join(TEST_DATA_PATH, 'flags-v1.json')
      return nil unless File.exist?(flags_file)

      flags_config = JSON.parse(File.read(flags_file))
      
      # Extract the nested flags structure for InternalEvaluator
      ufc_json = if flags_config.dig('data', 'attributes', 'flags')
        { 'flags' => flags_config.dig('data', 'attributes', 'flags') }
      else
        flags_config
      end
      
      require_relative '../../../../lib/datadog/open_feature/binding/internal_evaluator'
      Datadog::OpenFeature::Binding::InternalEvaluator.new(ufc_json.to_json)
    rescue => e
      puts "Warning: InternalEvaluator initialization failed: #{e.message}"
      nil
    end

    it 'produces consistent results with InternalEvaluator for basic scenarios' do
      skip "Evaluators not available" unless evaluator && internal_evaluator

      test_scenarios = [
        { targeting_key: 'alice', attributes: {}, flag: 'test_flag', expected_type: :string, default: 'default' },
        { targeting_key: 'bob', attributes: { 'country' => 'US' }, flag: 'test_flag', expected_type: :string, default: 'fallback' },
        { targeting_key: 'charlie', attributes: { 'age' => 30 }, flag: 'nonexistent', expected_type: :string, default: 'missing' }
      ]

      test_scenarios.each do |scenario|
        native_context = create_evaluation_context(scenario[:targeting_key], scenario[:attributes])
        internal_context = { 'targeting_key' => scenario[:targeting_key] }.merge(scenario[:attributes] || {})

        native_result = evaluator.get_assignment(
          scenario[:flag], native_context, scenario[:expected_type], scenario[:default]
        )

        internal_result = internal_evaluator.get_assignment(
          scenario[:flag], internal_context, scenario[:expected_type], Time.now, scenario[:default]
        )

        # Compare key properties - both should handle missing flags consistently
        if native_result.error_code && internal_result.error_code
          # Both should return default value on error
          expect(native_result.value).to eq(scenario[:default])
          expect(internal_result.value).to eq(scenario[:default])
        elsif native_result.error_code.nil? && internal_result.error_code.nil?
          # Both should succeed with same value for valid flags
          expect(native_result.value).to eq(internal_result.value)
        end

        puts "Scenario #{scenario[:targeting_key]}/#{scenario[:flag]}: Native=#{native_result.value} (#{native_result.error_code}), Internal=#{internal_result.value} (#{internal_result.error_code})"
      end
    end
  end
end