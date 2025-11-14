# frozen_string_literal: true

require 'json'
require_relative '../../../../lib/datadog/open_feature/binding/configuration'

RSpec.describe Datadog::OpenFeature::Binding::Configuration do
  let(:flags_v1_path) { File.join(__dir__, '../../../fixtures/ufc/flags-v1.json') }
  let(:flags_v1_json) { JSON.parse(File.read(flags_v1_path)) }
  let(:flag_config) { flags_v1_json }

  describe '.from_hash' do
    it 'parses the main flags-v1.json without errors' do
      expect { described_class.from_hash(flag_config) }.not_to raise_error
    end

    it 'extracts correct number of flags' do
      config = described_class.from_hash(flag_config)
      expect(config.flags.keys.count).to be > 10
    end

    it 'parses specific flags correctly' do
      config = described_class.from_hash(flag_config)

      empty_flag = config.flags['empty_flag']
      expect(empty_flag).not_to be_nil
      expect(empty_flag.key).to eq('empty_flag')
      expect(empty_flag.enabled).to be true
      expect(empty_flag.variation_type).to eq('STRING')

      disabled_flag = config.flags['disabled_flag']
      expect(disabled_flag).not_to be_nil
      expect(disabled_flag.enabled).to be false
      expect(disabled_flag.variation_type).to eq('INTEGER')
    end

    it 'parses numeric variations correctly' do
      config = described_class.from_hash(flag_config)

      numeric_flag = config.flags['numeric_flag']
      expect(numeric_flag).not_to be_nil
      expect(numeric_flag.variation_type).to eq('NUMERIC')

      if numeric_flag.variations['e']
        e_value = numeric_flag.variations['e'].value
        expect(e_value).to be_within(0.001).of(2.7182818)
      end
    end

    it 'handles all variation types present in test data' do
      config = described_class.from_hash(flag_config)

      variation_types = config.flags.values.map(&:variation_type).uniq
      expect(variation_types).to include('STRING', 'INTEGER', 'NUMERIC')
    end

    it 'parses allocations with rules and splits' do
      config = described_class.from_hash(flag_config)

      flags_with_allocations = config.flags.values.select { |f| f.allocations.any? }
      expect(flags_with_allocations).not_to be_empty

      flag_with_allocation = flags_with_allocations.first
      allocation = flag_with_allocation.allocations.first

      expect(allocation.key).to be_a(String)
      expect([true, false]).to include(allocation.do_log)
    end
  end

  describe '#get_flag' do
    let(:config) { described_class.from_hash(flag_config) }

    it 'returns existing flags' do
      flag = config.get_flag('empty_flag')
      expect(flag).not_to be_nil
      expect(flag.key).to eq('empty_flag')
    end

    it 'returns nil for non-existent flags' do
      flag = config.get_flag('does_not_exist')
      expect(flag).to be_nil
    end
  end

  describe 'error handling' do
    it 'handles empty configuration' do
      config = described_class.from_hash({})
      expect(config.flags).to be_empty
    end
  end
end
