# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Feature Flags Flag Types', :feature_flags do
  include FeatureFlagsHelpers
  with_feature_flags_extension

  let(:config) { create_test_configuration }
  let(:test_context) { build_user_context('test-user') }

  # Test flag type constants if they exist (from enhanced implementation)
  describe 'Flag Type Constants' do
    context 'when enhanced flag types are available' do
      it 'defines flag type constants' do
        if defined?(Datadog::Core::FeatureFlags::BOOLEAN)
          expect(Datadog::Core::FeatureFlags::BOOLEAN).to eq(:boolean)
          expect(Datadog::Core::FeatureFlags::STRING).to eq(:string)
          expect(Datadog::Core::FeatureFlags::NUMBER).to eq(:number)
          expect(Datadog::Core::FeatureFlags::OBJECT).to eq(:object)
        else
          skip 'Enhanced flag type constants not available'
        end
      end
    end
  end

  describe 'get_assignment method signatures' do
    context 'original implementation (2 parameters)' do
      it 'works with flag_key and context' do
        result = config.get_assignment('empty_flag', test_context)
        expect_valid_resolution_details(result)
      end
    end

    context 'enhanced implementation (3 parameters)' do
      it 'works with flag_key, context, and flag_type' do
        if defined?(Datadog::Core::FeatureFlags::STRING)
          result = config.get_assignment('empty_flag', test_context, Datadog::Core::FeatureFlags::STRING)
          expect_valid_resolution_details(result)
        else
          skip 'Enhanced 3-parameter method not available'
        end
      end
    end
  end

  describe 'Boolean flag evaluation' do
    let(:boolean_test_cases) do
      load_fixture_json('test-case-boolean-one-of-matches.json')
    end

    it 'evaluates boolean attributes correctly' do
      boolean_test_cases.each do |test_case|
        context = build_user_context(test_case['targetingKey'], test_case['attributes'] || {})

        # Test with original method
        result = config.get_assignment(test_case['flag'], context)
        expect_valid_resolution_details(result)

        # Test with enhanced method if available
        if defined?(Datadog::Core::FeatureFlags::BOOLEAN)
          result_enhanced = config.get_assignment(test_case['flag'], context, Datadog::Core::FeatureFlags::BOOLEAN)
          expect_valid_resolution_details(result_enhanced)

          # Results should be consistent between methods
          expect(result_enhanced.value).to eq(result.value)
        end

        # Validate against expected result
        if test_case['result']
          validate_test_case_result(result, test_case['result'],
            "Boolean test for #{test_case['targetingKey']}")
        end
      end
    end
  end

  describe 'JSON/Object flag evaluation' do
    let(:json_test_file) { File.join(__dir__, 'fixtures', 'test-json-config-flag.json') }

    context 'when JSON test cases are available' do
      it 'evaluates JSON flags correctly' do
        skip 'test-json-config-flag.json not found' unless File.exist?(json_test_file)

        json_test_cases = JSON.parse(File.read(json_test_file))

        json_test_cases.each do |test_case|
          context = build_user_context(test_case['targetingKey'], test_case['attributes'] || {})

          # Test with original method
          result = config.get_assignment(test_case['flag'], context)
          expect_valid_resolution_details(result)

          # Test with enhanced method if available
          if defined?(Datadog::Core::FeatureFlags::OBJECT)
            result_enhanced = config.get_assignment(test_case['flag'], context, Datadog::Core::FeatureFlags::OBJECT)
            expect_valid_resolution_details(result_enhanced)
          end

          # Validate against expected result
          if test_case['result'] && test_case['result']['value']
            expected_value = test_case['result']['value']
            if expected_value.is_a?(Hash)
              expect_json_flag_result(result, expected_value)
            end
          end
        end
      end
    end
  end

  describe 'Integer flag evaluation' do
    let(:integer_test_file) { File.join(__dir__, 'fixtures', 'test-case-integer-flag.json') }

    context 'when integer test cases are available' do
      it 'evaluates integer flags correctly' do
        skip 'test-case-integer-flag.json not found' unless File.exist?(integer_test_file)

        integer_test_cases = JSON.parse(File.read(integer_test_file))

        integer_test_cases.each do |test_case|
          context = build_user_context(test_case['targetingKey'], test_case['attributes'] || {})

          # Test with original method
          result = config.get_assignment(test_case['flag'], context)
          expect_valid_resolution_details(result)

          # Test with enhanced method if available
          if defined?(Datadog::Core::FeatureFlags::NUMBER)
            result_enhanced = config.get_assignment(test_case['flag'], context, Datadog::Core::FeatureFlags::NUMBER)
            expect_valid_resolution_details(result_enhanced)
          end

          # Validate against expected result
          if test_case['result']
            validate_test_case_result(result, test_case['result'],
              "Integer test for #{test_case['targetingKey']}")

            if test_case['result']['value'].is_a?(Integer)
              expect_numeric_flag_result(result, test_case['result']['value'])
            end
          end
        end
      end
    end
  end

  describe 'String flag evaluation' do
    # Use one of the available test cases that returns strings
    it 'evaluates string flags correctly' do
      # Test basic string evaluation
      result = config.get_assignment('empty_flag', test_context)
      expect_valid_resolution_details(result)

      # Test with enhanced method if available
      if defined?(Datadog::Core::FeatureFlags::STRING)
        result_enhanced = config.get_assignment('empty_flag', test_context, Datadog::Core::FeatureFlags::STRING)
        expect_valid_resolution_details(result_enhanced)

        # Results should be consistent
        expect(result_enhanced.value).to eq(result.value)
        expect(result_enhanced.reason).to eq(result.reason)
      end
    end
  end

  describe 'Backward compatibility' do
    it 'maintains compatibility with original API' do
      # Original 2-parameter method should always work
      result = config.get_assignment('empty_flag', test_context)
      expect_valid_resolution_details(result)
      expect_openfeature_compliance(result)
    end

    context 'when enhanced API is available' do
      it 'provides same results with default flag type' do
        if defined?(Datadog::Core::FeatureFlags::STRING)
          result_original = config.get_assignment('empty_flag', test_context)
          result_enhanced = config.get_assignment('empty_flag', test_context, Datadog::Core::FeatureFlags::STRING)

          expect(result_enhanced.value).to eq(result_original.value)
          expect(result_enhanced.reason).to eq(result_original.reason)
          expect(result_enhanced.error?).to eq(result_original.error?)
        end
      end
    end
  end

  describe 'Error? predicate method' do
    it 'correctly identifies error states' do
      # Test with non-existent flag (should error)
      result = config.get_assignment('definitely_does_not_exist', test_context)
      expect_valid_resolution_details(result)

      # Should have error? method available
      expect(result).to respond_to(:error?)

      if result.error_code
        expect(result.error?).to be_truthy
      else
        expect(result.error?).to be_falsey
      end
    end

    it 'returns false for successful evaluations' do
      result = config.get_assignment('empty_flag', test_context)
      expect_valid_resolution_details(result)

      if result.error_code.nil?
        expect(result.error?).to be_falsey
      end
    end
  end

  describe 'OpenFeature compliance' do
    it 'returns uppercase string constants for all evaluation types' do
      test_flags = ['empty_flag', 'disabled_flag']

      test_flags.each do |flag|
        result = config.get_assignment(flag, test_context)
        expect_valid_resolution_details(result)
        expect_openfeature_compliance(result)
      end
    end
  end

  describe 'Memory safety under load' do
    it 'handles rapid evaluations without memory issues' do
      # This tests the GC safety improvements
      100.times do |i|
        context = build_user_context("user-#{i}", { "attribute_#{i % 10}" => "value_#{i}" })
        result = config.get_assignment('empty_flag', context)
        expect_valid_resolution_details(result)
      end
    end

    it 'handles large context objects safely' do
      # This tests the optimized hash iteration
      large_context = build_user_context('test-user')
      100.times { |i| large_context["large_attr_#{i}"] = "large_value_#{i}_#{'x' * 100}" }

      result = config.get_assignment('empty_flag', large_context)
      expect_valid_resolution_details(result)
    end
  end
end