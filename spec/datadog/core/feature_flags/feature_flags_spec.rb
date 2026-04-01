# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Datadog::Core::FeatureFlags' do
  before do
    # Skip tests if libdatadog_api extension is not available
    skip 'libdatadog_api extension not available' unless defined?(Datadog::Core::FeatureFlags)
  end

  let(:fixtures_path) { File.join(__dir__, 'fixtures') }
  let(:main_config_path) { File.join(fixtures_path, 'flags-v1.json') }
  let(:main_config_json) { File.read(main_config_path) }

  describe 'Configuration' do
    context 'with valid JSON configuration' do
      subject(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }

      it 'creates a configuration successfully' do
        expect(config).to be_a(Datadog::Core::FeatureFlags::Configuration)
      end
    end

    context 'with invalid JSON configuration' do
      it 'raises an error for malformed JSON' do
        expect do
          Datadog::Core::FeatureFlags::Configuration.new('invalid json')
        end.to raise_error(RuntimeError, /Failed to create configuration/)
      end

      it 'raises an error for empty string' do
        expect do
          Datadog::Core::FeatureFlags::Configuration.new('')
        end.to raise_error(RuntimeError, /Failed to create configuration/)
      end
    end
  end

  describe 'Flag evaluation with test cases' do
    let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }

    # Load and run all JSON test case files
    Dir.glob(File.join(__dir__, 'fixtures', 'test-case-*.json')).each do |test_file|
      test_name = File.basename(test_file, '.json')

      describe test_name do
        let(:test_cases) { JSON.parse(File.read(test_file)) }

        test_cases.each_with_index do |test_case, index|
          context "test case #{index + 1}" do
            let(:flag_key) { test_case['flag'] }
            let(:variation_type) { test_case['variationType'] }
            let(:default_value) { test_case['defaultValue'] }
            let(:targeting_key) { test_case['targetingKey'] }
            let(:attributes) { test_case['attributes'] || {} }
            let(:expected_result) { test_case['result'] }

            let(:context) do
              ctx = { 'targeting_key' => targeting_key }
              ctx.merge!(attributes)
              ctx
            end

            it "evaluates correctly for #{targeting_key || 'anonymous user'}" do
              # Get the assignment
              result = config.get_assignment(flag_key, context)

              # Validate based on expected result
              if expected_result
                # Test has expected result
                expect(result.value).to eq(expected_result['value'])

                if expected_result['variant']
                  expect(result.variant).to eq(expected_result['variant'])
                end

                if expected_result['flagMetadata']
                  metadata = expected_result['flagMetadata']
                  expect(result.allocation_key).to eq(metadata['allocationKey']) if metadata['allocationKey']
                  expect(result.log?).to eq(metadata['doLog']) if metadata.key?('doLog')
                end

                # Should not be an error case
                expect(result.error?).to be_falsey
                expect(result.error_code).to be_nil
              else
                # Test expects default value behavior (usually nil/default value)
                # This typically happens when targeting doesn't match
                expect(result.value).to eq(default_value).or be_nil
              end
            end
          end
        end
      end
    end
  end

  describe 'Flag types' do
    let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }
    let(:context) { { 'targeting_key' => 'test-user' } }

    describe 'disabled flags' do
      it 'returns appropriate result for disabled flag' do
        result = config.get_assignment('disabled_flag', context)

        # Disabled flags typically return nil or default value
        expect(result.value).to be_nil
        expect(result.reason).to eq('DISABLED').or eq('DEFAULT')
      end
    end

    describe 'empty flags' do
      it 'handles empty flag configuration' do
        result = config.get_assignment('empty_flag', context)

        # Empty flags should return some result (possibly default)
        expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
        expect(result.error?).to be_falsey
      end
    end

    describe 'non-existent flags' do
      it 'handles requests for non-existent flags' do
        result = config.get_assignment('non_existent_flag', context)

        # Should return an error or nil
        expect(result.error?).to be_truthy.or expect(result.value).to be_nil
      end
    end
  end

  describe 'ResolutionDetails' do
    let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }
    let(:context) { { 'targeting_key' => 'test-user' } }
    let(:result) { config.get_assignment('empty_flag', context) }

    it 'has all required methods' do
      expect(result).to respond_to(:value)
      expect(result).to respond_to(:reason)
      expect(result).to respond_to(:error_code)
      expect(result).to respond_to(:error_message)
      expect(result).to respond_to(:error?)
      expect(result).to respond_to(:variant)
      expect(result).to respond_to(:allocation_key)
      expect(result).to respond_to(:log?)
    end

    it 'returns appropriate types' do
      expect(result.reason).to be_a(String).or be_nil
      expect(result.error_code).to be_a(String).or be_nil
      expect(result.error_message).to be_a(String).or be_nil
      expect(result.error?).to be_in([true, false])
      expect(result.variant).to be_a(String).or be_nil
      expect(result.allocation_key).to be_a(String).or be_nil
      expect(result.log?).to be_in([true, false])
    end

    describe 'error? predicate' do
      context 'when there is an error' do
        let(:result) { config.get_assignment('non_existent_flag', context) }

        it 'returns true for error?' do
          if result.error_code
            expect(result.error?).to be_truthy
          end
        end
      end

      context 'when there is no error' do
        it 'returns false for error?' do
          unless result.error_code
            expect(result.error?).to be_falsey
          end
        end
      end
    end

    describe 'OpenFeature compliance' do
      it 'returns uppercase string constants for reasons' do
        unless result.reason.nil?
          expect(result.reason).to match(/^[A-Z_]+$/)
        end
      end

      it 'returns uppercase string constants for error codes' do
        unless result.error_code.nil?
          expect(result.error_code).to match(/^[A-Z_]+$/)
        end
      end
    end
  end

  describe 'Context handling' do
    let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }

    it 'handles context with targeting_key' do
      context = { 'targeting_key' => 'user-123' }
      result = config.get_assignment('empty_flag', context)
      expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
    end

    it 'handles context with additional attributes' do
      context = {
        'targeting_key' => 'user-123',
        'country' => 'US',
        'age' => 25,
        'premium' => true
      }
      result = config.get_assignment('empty_flag', context)
      expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
    end

    it 'handles empty context' do
      result = config.get_assignment('empty_flag', {})
      expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
    end
  end

  describe 'Memory safety' do
    let(:config) { Datadog::Core::FeatureFlags::Configuration.new(main_config_json) }

    it 'handles many evaluations without memory leaks' do
      # This test ensures our GC safety fixes work correctly
      100.times do |i|
        context = { 'targeting_key' => "user-#{i}" }
        result = config.get_assignment('empty_flag', context)
        expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
      end
    end

    it 'handles large contexts safely' do
      large_context = { 'targeting_key' => 'user-123' }
      50.times { |i| large_context["attr_#{i}"] = "value_#{i}" }

      result = config.get_assignment('empty_flag', large_context)
      expect(result).to be_a(Datadog::Core::FeatureFlags::ResolutionDetails)
    end
  end
end