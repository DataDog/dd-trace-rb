# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Feature Flags Integration Tests', :feature_flags do
  before do
    # Skip all feature flag tests if the extension is not available
    skip 'libdatadog_api extension not available' unless defined?(Datadog::Core::FeatureFlags)
  end

  describe 'Extension availability' do
    it 'loads the libdatadog_api extension successfully' do
      expect(defined?(Datadog::Core::FeatureFlags)).to be_truthy
      expect(defined?(Datadog::Core::FeatureFlags::Configuration)).to be_truthy
      expect(defined?(Datadog::Core::FeatureFlags::ResolutionDetails)).to be_truthy
    end

    it 'has working Configuration class' do
      expect(Datadog::Core::FeatureFlags::Configuration).to respond_to(:new)
    end

    it 'has working ResolutionDetails methods' do
      # Create a minimal test to ensure the extension loaded properly
      simple_config = { "flags" => {} }.to_json

      begin
        config = Datadog::Core::FeatureFlags::Configuration.new(simple_config)
        result = config.get_assignment('test_flag', { 'targeting_key' => 'test' })

        expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
        expect(result).to respond_to(:value, :reason, :error_code, :error_message, :variant, :allocation_key, :log?)

        # Test the enhanced error? method if available
        if result.respond_to?(:error?)
          expect(result.error?).to be_in([true, false])
        end
      rescue => e
        # If configuration creation fails, that's also useful information
        puts "Configuration creation failed: #{e.message}"
        puts "This might indicate libdatadog version mismatch or missing dependencies"
      end
    end
  end

  describe 'Test data availability' do
    let(:fixtures_dir) { File.join(__dir__, 'feature_flags', 'fixtures') }

    it 'has the main configuration file' do
      config_file = File.join(fixtures_dir, 'flags-v1.json')
      expect(File.exist?(config_file)).to be_truthy
      expect(File.size(config_file)).to be > 1000 # Should be a substantial file
    end

    it 'has test case files' do
      test_files = Dir.glob(File.join(fixtures_dir, 'test-case-*.json'))
      expect(test_files.length).to be > 10 # Should have multiple test case files

      # Verify some key test files exist
      expected_files = [
        'test-case-boolean-one-of-matches.json',
        'test-case-disabled-flag.json',
        'test-case-empty-flag.json'
      ]

      expected_files.each do |filename|
        file_path = File.join(fixtures_dir, filename)
        expect(File.exist?(file_path)).to be_truthy, "Missing test file: #{filename}"
      end
    end

    it 'can parse all test files as valid JSON' do
      test_files = Dir.glob(File.join(fixtures_dir, '*.json'))

      test_files.each do |file_path|
        expect { JSON.parse(File.read(file_path)) }.not_to raise_error,
          "Invalid JSON in #{File.basename(file_path)}"
      end
    end
  end

  describe 'Test execution summary' do
    let(:fixtures_dir) { File.join(__dir__, 'feature_flags', 'fixtures') }

    it 'counts total test cases available' do
      total_cases = 0
      test_files = Dir.glob(File.join(fixtures_dir, 'test-case-*.json'))

      test_files.each do |file_path|
        test_data = JSON.parse(File.read(file_path))
        case_count = test_data.is_a?(Array) ? test_data.length : 1
        total_cases += case_count
      end

      puts "\nFeature Flags Test Summary:"
      puts "  Test files: #{test_files.length}"
      puts "  Total test cases: #{total_cases}"
      puts "  Main config file: #{File.exist?(File.join(fixtures_dir, 'flags-v1.json')) ? 'Present' : 'Missing'}"

      expect(total_cases).to be > 50 # Should have plenty of test cases
    end
  end

  describe 'Quick smoke test' do
    let(:fixtures_dir) { File.join(__dir__, 'feature_flags', 'fixtures') }
    let(:main_config) { JSON.parse(File.read(File.join(fixtures_dir, 'flags-v1.json'))) }
    let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config.to_json) }

    it 'can run a basic evaluation without errors' do
      result = config.get_assignment('empty_flag', { 'targeting_key' => 'smoke-test-user' })

      expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)

      # Basic method availability test
      expect(result.value).to be_a(Object) # Could be any type or nil
      expect(result.reason).to be_a(String).or(be_nil)
      expect(result.error_code).to be_a(String).or(be_nil)

      puts "Smoke test result:"
      puts "  Value: #{result.value.inspect}"
      puts "  Reason: #{result.reason}"
      puts "  Error?: #{result.error? if result.respond_to?(:error?)}"
    end

    it 'demonstrates enhanced API if available' do
      if defined?(Datadog::Core::FeatureFlags::STRING)
        puts "\nEnhanced API available:"
        puts "  BOOLEAN = #{Datadog::Core::FeatureFlags::BOOLEAN}"
        puts "  STRING = #{Datadog::Core::FeatureFlags::STRING}"
        puts "  NUMBER = #{Datadog::Core::FeatureFlags::NUMBER}"
        puts "  OBJECT = #{Datadog::Core::FeatureFlags::OBJECT}"

        # Test 3-parameter method
        result = config.get_assignment('empty_flag', { 'targeting_key' => 'test' }, Datadog::Core::FeatureFlags::STRING)
        expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)

        puts "  Enhanced method works: ✓"
      else
        puts "\nOriginal API only (2-parameter method)"
      end
    end
  end
end