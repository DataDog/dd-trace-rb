# frozen_string_literal: true

module FeatureFlagsHelpers
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def with_feature_flags_extension
      before do
        # Skip tests if libdatadog_api extension is not available
        skip 'libdatadog_api extension not available' unless defined?(Datadog::Core::FeatureFlags)
      end
    end
  end

  def feature_flags_available?
    defined?(Datadog::Core::FeatureFlags)
  end

  def load_fixture_json(filename)
    fixture_path = File.join(__dir__, '..', 'datadog', 'core', 'feature_flags', 'fixtures', filename)
    JSON.parse(File.read(fixture_path))
  end

  def main_test_config
    @main_test_config ||= load_fixture_json('flags-v1.json')
  end

  def create_test_configuration
    Datadog::Core::FeatureFlags::Configuration.new(main_test_config.to_json)
  end

  def evaluate_flag(config, flag_key, context = {})
    default_context = { 'targeting_key' => 'test-user' }
    full_context = default_context.merge(context)
    config.get_assignment(flag_key, full_context)
  end

  def expect_valid_resolution_details(result)
    expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
    expect(result).to respond_to(:value)
    expect(result).to respond_to(:reason)
    expect(result).to respond_to(:error_code)
    expect(result).to respond_to(:error_message)
    expect(result).to respond_to(:error?)
    expect(result).to respond_to(:variant)
    expect(result).to respond_to(:allocation_key)
    expect(result).to respond_to(:log?)
  end

  def expect_successful_evaluation(result, expected_value = nil)
    expect_valid_resolution_details(result)
    expect(result.error?).to be_falsey
    expect(result.value).to eq(expected_value) if expected_value
  end

  def expect_error_evaluation(result, expected_error_code = nil)
    expect_valid_resolution_details(result)
    expect(result.error?).to be_truthy
    expect(result.error_code).to eq(expected_error_code) if expected_error_code
  end

  def expect_openfeature_compliance(result)
    # Reasons should be uppercase strings
    unless result.reason.nil?
      expect(result.reason).to be_a(String)
      expect(result.reason).to match(/^[A-Z_]+$/)
    end

    # Error codes should be uppercase strings
    unless result.error_code.nil?
      expect(result.error_code).to be_a(String)
      expect(result.error_code).to match(/^[A-Z_]+$/)
    end
  end

  # Test data validation helpers
  def validate_test_case_result(actual_result, expected_result, context_description = '')
    if expected_result
      expect(actual_result.value).to eq(expected_result['value']),
        "#{context_description} - Value mismatch"

      if expected_result['variant']
        expect(actual_result.variant).to eq(expected_result['variant']),
          "#{context_description} - Variant mismatch"
      end

      if expected_result['flagMetadata']
        metadata = expected_result['flagMetadata']

        if metadata['allocationKey']
          expect(actual_result.allocation_key).to eq(metadata['allocationKey']),
            "#{context_description} - Allocation key mismatch"
        end

        if metadata.key?('doLog')
          expect(actual_result.log?).to eq(metadata['doLog']),
            "#{context_description} - DoLog flag mismatch"
        end
      end

      expect(actual_result.error?).to be_falsey,
        "#{context_description} - Unexpected error: #{actual_result.error_code}"
    else
      # No expected result usually means default behavior
      expect(actual_result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails),
        "#{context_description} - Should return ResolutionDetails"
    end
  end

  # Context builders for common test scenarios
  def build_user_context(targeting_key, additional_attrs = {})
    context = { 'targeting_key' => targeting_key.to_s }
    context.merge!(additional_attrs.transform_keys(&:to_s))
    context
  end

  def build_anonymous_context(additional_attrs = {})
    additional_attrs.transform_keys(&:to_s)
  end

  # Flag type test helpers
  def expect_boolean_flag_result(result, expected_bool)
    expect_successful_evaluation(result)
    expect(result.value).to be_in([true, false])
    expect(result.value).to eq(expected_bool) if expected_bool
  end

  def expect_string_flag_result(result, expected_string = nil)
    expect_successful_evaluation(result)
    expect(result.value).to be_a(String).or(be_nil)
    expect(result.value).to eq(expected_string) if expected_string
  end

  def expect_numeric_flag_result(result, expected_number = nil)
    expect_successful_evaluation(result)
    expect(result.value).to be_a(Numeric).or(be_nil)
    expect(result.value).to eq(expected_number) if expected_number
  end

  def expect_json_flag_result(result, expected_json = nil)
    expect_successful_evaluation(result)
    # JSON flags can return Hash objects or JSON strings
    expect(result.value).to be_a(Hash).or(be_a(String)).or(be_nil)

    if expected_json
      if result.value.is_a?(String)
        parsed_value = JSON.parse(result.value) rescue result.value
        expect(parsed_value).to eq(expected_json)
      else
        expect(result.value).to eq(expected_json)
      end
    end
  end
end

# Add to RSpec configuration
RSpec.configure do |config|
  config.include FeatureFlagsHelpers
end